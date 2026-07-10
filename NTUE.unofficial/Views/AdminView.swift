import SwiftUI

/// 管理後台 — add/edit/delete the CloudKit-backed remote data
/// (校園行事曆、學期起迄日期、強制更新設定) straight from the app, no Console needed.
/// Writes go to whichever CloudKit environment the running build is signed for
/// (Xcode debug = Development; release builds = Production). Reachable only from
/// the developer tools, which are gated by the CloudKit whitelist
/// (`DeveloperAccessService`), so ordinary users never see it.
struct AdminView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { EventsAdminList() } label: {
                    Label("校園行事曆", systemImage: "calendar.badge.plus")
                }
                NavigationLink { TermsAdminList() } label: {
                    Label("學期起迄日期", systemImage: "calendar")
                }
                NavigationLink { ConfigAdminForm() } label: {
                    Label("強制更新設定", systemImage: "arrow.up.circle")
                }
            } header: {
                Text("管理項目")
            }

            Section {
                LabeledContent("Container", value: CloudKitConfig.containerID)
            } header: {
                Text("連線")
            } footer: {
                Text("寫入的環境由 build 決定:Xcode Debug 連 Development;若已在 entitlement 設 environment=Production,則連正式環境。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("管理後台")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 校園行事曆

private struct EventsAdminList: View {
    @State private var config = RemoteConfigService.shared
    @State private var draft: EventDraft?

    var body: some View {
        List {
            if config.events.isEmpty {
                Text("尚無活動,點右上角 + 新增。").foregroundStyle(.secondary)
            }
            ForEach(config.events) { e in
                Button { draft = EventDraft(event: e) } label: { row(e) }
                    .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                let ids = indexSet.map { config.events[$0].id }
                Task { for id in ids { try? await CloudKitAdmin.deleteEvent(id: id) }; await config.refresh() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("校園行事曆")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { draft = EventDraft(event: nil) } label: { Image(systemName: "plus") }
        }
        .refreshable { await config.refresh() }
        .task { await config.refresh() }
        .sheet(item: $draft) { d in
            NavigationStack { EventEditor(existing: d.event) }
        }
    }

    private func row(_ e: CalendarEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: e.category.icon).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.subheadline.bold())
                Text("\(dateText(e.date))\(e.endDate.map { " – " + dateText($0) } ?? "")　·　\(e.category.label)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "yyyy/M/d"
        return f.string(from: d)
    }
}

private struct EventDraft: Identifiable {
    let id = UUID()
    let event: CalendarEvent?
}

private struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    let existing: CalendarEvent?

    @State private var title: String
    @State private var date: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var category: CalendarEvent.Category
    @State private var note: String
    @State private var allDay: Bool
    @State private var saving = false
    @State private var error: String?

    private let recordID: String

    init(existing: CalendarEvent?) {
        self.existing = existing
        self.recordID = existing?.id ?? CloudKitAdmin.newEventID()
        _title = State(initialValue: existing?.title ?? "")
        _date = State(initialValue: existing?.date ?? Date())
        _hasEnd = State(initialValue: existing?.endDate != nil)
        _endDate = State(initialValue: existing?.endDate ?? existing?.date ?? Date())
        _category = State(initialValue: existing?.category ?? .general)
        _note = State(initialValue: existing?.note ?? "")
        _allDay = State(initialValue: existing?.allDay ?? true)
    }

    var body: some View {
        Form {
            Section {
                TextField("活動名稱", text: $title)
                Picker("分類", selection: $category) {
                    ForEach(CalendarEvent.Category.allCases, id: \.self) { c in
                        Label(c.label, systemImage: c.icon).tag(c)
                    }
                }
            }
            Section {
                Toggle("整天", isOn: $allDay)
                DatePicker("開始", selection: $date,
                           displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                Toggle("多日活動", isOn: $hasEnd.animation())
                if hasEnd {
                    DatePicker("結束", selection: $endDate, in: date..., displayedComponents: .date)
                }
            }
            Section("備註（可空）") {
                TextField("補充說明", text: $note, axis: .vertical).lineLimit(1...4)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(existing == nil ? "新增活動" : "編輯活動")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() }
                else { Button("儲存") { save() }.disabled(title.isEmpty) }
            }
        }
    }

    private func save() {
        saving = true; error = nil
        let event = CalendarEvent(
            id: recordID, title: title, date: date,
            endDate: hasEnd ? endDate : nil, category: category,
            note: note.isEmpty ? nil : note, allDay: allDay)
        Task {
            do {
                try await CloudKitAdmin.save(event: event)
                await RemoteConfigService.shared.refresh()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

// MARK: - 學期起迄日期

private struct TermsAdminList: View {
    @State private var terms: [AcademicTerm] = AcademicCalendar.terms
    @State private var draft: TermDraft?

    var body: some View {
        List {
            ForEach(terms, id: \.code) { t in
                Button { draft = TermDraft(term: t) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.subheadline.bold())
                        Text("\(dateText(t.start)) 開學 · 16週 \(dateText(t.end16)) · 18週 \(dateText(t.end18))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                let codes = indexSet.map { terms[$0].code }
                Task { for c in codes { try? await CloudKitAdmin.deleteTerm(code: c) }; await reload() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("學期起迄日期")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { draft = TermDraft(term: nil) } label: { Image(systemName: "plus") } }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $draft, onDismiss: { Task { await reload() } }) { d in
            NavigationStack { TermEditor(existing: d.term) }
        }
    }

    private func reload() async {
        await RemoteConfigService.shared.refresh()
        terms = AcademicCalendar.terms
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "M/d"
        return f.string(from: d)
    }
}

private struct TermDraft: Identifiable {
    let id = UUID()
    let term: AcademicTerm?
}

private struct TermEditor: View {
    @Environment(\.dismiss) private var dismiss
    let existing: AcademicTerm?

    @State private var code: String
    @State private var name: String
    @State private var start: Date
    @State private var end16: Date
    @State private var end18: Date
    @State private var saving = false
    @State private var error: String?

    init(existing: AcademicTerm?) {
        self.existing = existing
        _code = State(initialValue: existing?.code ?? "")
        _name = State(initialValue: existing?.name ?? "")
        _start = State(initialValue: existing?.start ?? Date())
        _end16 = State(initialValue: existing?.end16 ?? Date())
        _end18 = State(initialValue: existing?.end18 ?? Date())
    }

    var body: some View {
        Form {
            Section("基本") {
                TextField("代碼（例 1151）", text: $code)
                    .disabled(existing != nil)   // recordName 綁 code,編輯時不改
                TextField("名稱（例 115 學年度 第 1 學期）", text: $name)
            }
            Section("日期") {
                DatePicker("開學", selection: $start, displayedComponents: .date)
                DatePicker("課程結束（16 週）", selection: $end16, displayedComponents: .date)
                DatePicker("學期結束（18 週）", selection: $end18, displayedComponents: .date)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(existing == nil ? "新增學期" : "編輯學期")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() }
                else { Button("儲存") { save() }.disabled(code.isEmpty || name.isEmpty) }
            }
        }
    }

    private func save() {
        saving = true; error = nil
        let term = AcademicTerm(code: code, name: name, start: start, end16: end16, end18: end18)
        Task {
            do {
                try await CloudKitAdmin.save(term: term)
                await RemoteConfigService.shared.refresh()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

// MARK: - 強制更新設定

private struct ConfigAdminForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minVersion: String
    @State private var latestVersion: String
    @State private var updateURL: String
    @State private var updateTitle: String
    @State private var updateMessage: String
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false

    init() {
        let c = RemoteConfigService.shared.appConfig
        _minVersion = State(initialValue: c.minVersion ?? "")
        _latestVersion = State(initialValue: c.latestVersion ?? "")
        _updateURL = State(initialValue: c.updateURL ?? "")
        _updateTitle = State(initialValue: c.updateTitle ?? "")
        _updateMessage = State(initialValue: c.updateMessage ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("最低版本（例 1.5.0）", text: $minVersion)
                    .keyboardType(.numbersAndPunctuation)
                TextField("最新版本（顯示用,可空）", text: $latestVersion)
                    .keyboardType(.numbersAndPunctuation)
            } header: {
                Text("版本")
            } footer: {
                Text("目前 App 版本 \(AppConfig.currentVersion)。低於「最低版本」的使用者一開 App 就會被更新畫面擋住;設 0.0.0 等於關閉強制更新。")
            }
            Section("更新畫面文字（可空,有預設）") {
                TextField("標題", text: $updateTitle)
                TextField("內文", text: $updateMessage, axis: .vertical).lineLimit(2...5)
                TextField("App Store 連結", text: $updateURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }
            if saved {
                Section { Label("已儲存", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("強制更新設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else { Button("儲存") { save() } }
            }
        }
    }

    private func save() {
        saving = true; error = nil; saved = false
        var cfg = AppConfig()
        cfg.minVersion = minVersion.isEmpty ? nil : minVersion
        cfg.latestVersion = latestVersion.isEmpty ? nil : latestVersion
        cfg.updateURL = updateURL.isEmpty ? nil : updateURL
        cfg.updateTitle = updateTitle.isEmpty ? nil : updateTitle
        cfg.updateMessage = updateMessage.isEmpty ? nil : updateMessage
        Task {
            do {
                try await CloudKitAdmin.save(config: cfg)
                await RemoteConfigService.shared.refresh()
                saving = false; saved = true
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}
