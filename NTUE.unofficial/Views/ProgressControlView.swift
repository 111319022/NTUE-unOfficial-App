import SwiftUI

struct ProgressControlView: View {
    @Environment(AppState.self) private var appState
    @State private var pdfFile: PreviewFile?
    @State private var preparing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                introCard
                legendCard
                downloadButton
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("修業進度管制")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pdfFile) { file in
            QuickLookPreview(url: file.url).ignoresSafeArea()
        }
        .alert("無法取得檢核表", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("確定", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var introCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("學分檢核表", systemImage: "checklist")
                    .font(.headline)
                Text("這是學校官方的「學生已修習學分檢核表」，列出各類別應修／實修學分與修課狀態，是畢業審查的依據。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legendCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("檢核表顏色說明").font(.subheadline.bold())
                legendRow(.blue, "已修課程，成績已上鎖")
                legendRow(.purple, "已修課程，成績未上鎖")
                legendRow(.brown, "已修課程，但非課架內")
            }
        }
    }

    private func legendRow(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var downloadButton: some View {
        VStack(spacing: 10) {
            Button {
                Task { await preparePDF() }
            } label: {
                HStack {
                    if preparing { ProgressView().tint(.white) }
                    else { Image(systemName: "doc.richtext") }
                    Text("下載學分檢核表 PDF")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(preparing)

            if preparing {
                Text("正在產生檢核表…").font(.caption).foregroundStyle(.secondary)
            }
            Text("產生後可儲存到「檔案」或分享。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    private func preparePDF() async {
        preparing = true
        errorMessage = nil
        do {
            let url = try await NTUEService.shared.gradCreditCheckPDF(studentId: appState.studentInfo.studentId)
            pdfFile = PreviewFile(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
        preparing = false
    }
}
