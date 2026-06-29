import SwiftUI

@Observable
@MainActor
final class EnrollmentCertificateViewModel {
    var cert = EnrollmentCertificate()
    var isLoading = false
    var errorMessage: String?

    private let service = NTUEService.shared

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            cert = try await service.loadEnrollmentCertificate()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct EnrollmentCertificateView: View {
    @State private var vm = EnrollmentCertificateViewModel()
    @State private var pdfFile: PreviewFile?
    @State private var preparing: Bool = false
    @State private var pdfError: String?

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("載入在學資訊…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage {
                ContentUnavailableView {
                    Label("載入失敗", systemImage: "wifi.slash")
                } description: { Text(error) } actions: {
                    Button("重試") { Task { await vm.load() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        chineseCard
                        englishCard
                        pdfButton
                    }
                    .padding(16)
                }
                .background(Theme.background)
            }
        }
        .navigationTitle("在學證明")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.cert.isEmpty { await vm.load() } }
        .sheet(item: $pdfFile) { file in
            QuickLookPreview(url: file.url).ignoresSafeArea()
        }
        .alert("PDF 產生失敗", isPresented: Binding(get: { pdfError != nil }, set: { if !$0 { pdfError = nil } })) {
            Button("確定", role: .cancel) { pdfError = nil }
        } message: { Text(pdfError ?? "") }
    }

    private var pdfButton: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                pdfDownloadButton(title: "中文 PDF", english: false)
                pdfDownloadButton(title: "English PDF", english: true)
            }
            if preparing {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("正在產生 PDF…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("產生官方正式在學證明，可直接儲存或分享。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private func pdfDownloadButton(title: String, english: Bool) -> some View {
        Button {
            Task { await preparePDF(english: english) }
        } label: {
            Label(title, systemImage: "doc.richtext")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(preparing)
    }

    private func preparePDF(english: Bool) async {
        preparing = true
        pdfError = nil
        do {
            let url = try await NTUEService.shared.enrollmentCertificatePDF(english: english)
            pdfFile = PreviewFile(url: url)
        } catch {
            pdfError = error.localizedDescription
        }
        preparing = false
    }

    private var headerCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.cert.name).font(.title3.bold())
                    Text(vm.cert.studentId).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if !vm.cert.year.isEmpty {
                    Pill(text: "\(vm.cert.year) 學年度 第 \(vm.cert.semester) 學期", color: Theme.accent)
                }
            }
        }
    }

    private var chineseCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("中文在學資訊", systemImage: "character.book.closed").font(.subheadline.bold())
                infoRow("生日", vm.cert.birthday)
                infoRow("科系", vm.cert.department)
                infoRow("年級", vm.cert.grade)
                infoRow("處室", vm.cert.office)
            }
        }
    }

    private var englishCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("English", systemImage: "globe").font(.subheadline.bold())
                infoRow("Name", vm.cert.englishName)
                infoRow("Department", vm.cert.englishDepartment)
                infoRow("Admission", vm.cert.admissionTerm)
                if !vm.cert.classTypeStatement.isEmpty {
                    infoRow("Status", vm.cert.classTypeStatement)
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
