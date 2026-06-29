import SwiftUI

@Observable
@MainActor
final class PublicScheduleViewModel {
    var options = PublicScheduleOptions()
    var year = ""
    var semester = ""
    var selectedClass: NamedOption?
    var courses: [PublicCourse] = []

    var isLoadingOptions = false
    var isQuerying = false
    var hasSearched = false
    var errorMessage: String?

    private let service = NTUEService.shared

    func loadOptions() async {
        guard options.classes.isEmpty else { return }
        isLoadingOptions = true
        errorMessage = nil
        do {
            options = try await service.loadPublicScheduleOptions()
            year = options.defaultYear
            semester = options.defaultSemester
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingOptions = false
    }

    func search() async {
        guard let cls = selectedClass else { return }
        isQuerying = true
        hasSearched = true
        errorMessage = nil
        do {
            courses = try await service.queryPublicSchedule(
                token: options.token, year: year, semester: semester, classId: cls.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isQuerying = false
    }

    var yearName: String { options.years.first { $0.id == year }?.name ?? year }
    var semesterName: String { options.semesters.first { $0.id == semester }?.name ?? semester }
}

struct PublicScheduleView: View {
    @State private var vm = PublicScheduleViewModel()
    @State private var showClassPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                filterCard
                results
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("公開課表查詢")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadOptions() }
        .sheet(isPresented: $showClassPicker) {
            OptionPickerSheet(title: "選擇班級", options: vm.options.classes, selection: $vm.selectedClass)
        }
    }

    // MARK: - Filter card

    private var filterCard: some View {
        Card {
            VStack(spacing: 14) {
                if vm.isLoadingOptions {
                    HStack { ProgressView(); Text("載入選項…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 12) {
                        menuField(title: "學年", value: vm.yearName) {
                            ForEach(vm.options.years) { y in
                                Button(y.name) { vm.year = y.id }
                            }
                        }
                        menuField(title: "學期", value: vm.semesterName) {
                            ForEach(vm.options.semesters) { s in
                                Button(s.name) { vm.semester = s.id }
                            }
                        }
                    }

                    Button {
                        showClassPicker = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("班級").font(.caption).foregroundStyle(.secondary)
                                Text(vm.selectedClass?.name ?? "請選擇班級")
                                    .foregroundStyle(vm.selectedClass == nil ? .secondary : .primary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await vm.search() }
                    } label: {
                        HStack {
                            if vm.isQuerying { ProgressView().tint(.white) }
                            else { Image(systemName: "magnifyingglass") }
                            Text("查詢")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(vm.selectedClass == nil || vm.isQuerying)
                }
            }
        }
    }

    private func menuField<Content: View>(title: String, value: String, @ViewBuilder menu: () -> Content) -> some View {
        Menu {
            menu()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if let error = vm.errorMessage {
            ContentUnavailableView {
                Label("查詢失敗", systemImage: "exclamationmark.triangle")
            } description: { Text(error) }
        } else if vm.isQuerying {
            ProgressView().padding(.top, 40)
        } else if vm.hasSearched && vm.courses.isEmpty {
            ContentUnavailableView("查無課程", systemImage: "magnifyingglass")
                .padding(.top, 20)
        } else if !vm.courses.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(vm.selectedClass?.name ?? "")　共 \(vm.courses.count) 門")
                    .font(.subheadline.bold())
                    .padding(.leading, 4)
                ForEach(vm.courses) { PublicCourseCard(course: $0) }
            }
        } else {
            Text("選擇班級後按「查詢」")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 30)
        }
    }
}

struct PublicCourseCard: View {
    let course: PublicCourse

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name).font(.headline)
                        if !course.engName.isEmpty {
                            Text(course.engName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(course.credit) 學分").font(.subheadline.bold()).foregroundStyle(Theme.accent)
                }
                HStack(spacing: 6) {
                    if !course.choose.isEmpty {
                        Pill(text: course.choose, color: course.isRequired ? Theme.accent : .blue)
                    }
                    if !course.teacher.isEmpty { Pill(text: course.teacher, color: .gray) }
                    if !course.language.isEmpty && course.language != "中文" {
                        Pill(text: course.language, color: .teal)
                    }
                }
                if !course.time.isEmpty || !course.classroom.isEmpty {
                    HStack(spacing: 14) {
                        if !course.time.isEmpty {
                            Label(course.time, systemImage: "clock").lineLimit(2)
                        }
                        if !course.classroom.isEmpty {
                            Label(course.classroom, systemImage: "mappin.and.ellipse")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A searchable single-selection picker presented as a sheet.
struct OptionPickerSheet: View {
    let title: String
    let options: [NamedOption]
    @Binding var selection: NamedOption?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [NamedOption] {
        query.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { option in
                Button {
                    selection = option
                    dismiss()
                } label: {
                    HStack {
                        Text(option.name).foregroundStyle(.primary)
                        Spacer()
                        if option.id == selection?.id {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜尋班級")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } }
            }
        }
    }
}
