import SwiftUI
import Charts

/// 成績分析 — visualises the aggregated transcript: per-semester GPA trend,
/// per-semester credits, and the overall score distribution. Reuses
/// `TranscriptViewModel` (same data that powers 歷年總表) so nothing is refetched
/// when it's already loaded.
struct GradeAnalysisView: View {
    var vm: TranscriptViewModel

    /// One semester's aggregates, oldest → newest for left-to-right charts.
    private struct Point: Identifiable {
        let id: String
        let label: String
        let gpa: Double?
        let credits: Double
    }

    private var points: [Point] {
        vm.semesters
            .sorted { ($0.selection.year, $0.selection.semester) < ($1.selection.year, $1.selection.semester) }
            .map {
                Point(id: $0.selection.id,
                      label: $0.selection.compactLabel,
                      gpa: TranscriptViewModel.weightedAverage($0.grades),
                      credits: TranscriptViewModel.credits($0.grades))
            }
    }

    /// Score buckets across every scored course.
    private struct Bucket: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let color: Color
    }

    private var distribution: [Bucket] {
        let scores = vm.semesters.flatMap(\.grades).compactMap(\.scoreValue)
        func n(_ range: Range<Double>) -> Int { scores.filter { range.contains($0) }.count }
        return [
            Bucket(label: "90+", count: scores.filter { $0 >= 90 }.count, color: Theme.scoreColor(95)),
            Bucket(label: "80-89", count: n(80..<90), color: Theme.scoreColor(85)),
            Bucket(label: "70-79", count: n(70..<80), color: Theme.scoreColor(75)),
            Bucket(label: "60-69", count: n(60..<70), color: Theme.scoreColor(65)),
            Bucket(label: "<60", count: scores.filter { $0 < 60 }.count, color: Theme.scoreColor(40)),
        ]
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.semesters.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在彙整歷年成績…").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.semesters.allSatisfy({ $0.grades.isEmpty }) {
                ContentUnavailableView("沒有可分析的成績", systemImage: "chart.xyaxis.line")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let p = vm.progress, p.done < p.total {
                            Label("載入中 \(p.done)/\(p.total) 學期…", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        summaryCard
                        gpaTrendCard
                        creditsCard
                        distributionCard
                    }
                    .padding(16)
                }
                .background(Theme.background)
            }
        }
        .navigationTitle("成績分析")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .task { await vm.load() }
    }

    // MARK: - Cards

    private var summaryCard: some View {
        Card {
            HStack {
                stat("累計學分", String(format: "%g", vm.totalCredits))
                Divider().frame(height: 36)
                stat("累計加權平均",
                     vm.cumulativeGPA.map { String(format: "%.2f", $0) } ?? "—",
                     color: Theme.scoreColor(vm.cumulativeGPA))
                Divider().frame(height: 36)
                stat("學期數", "\(points.filter { !$0.credits.isZero }.count)")
            }
        }
    }

    private var gpaTrendCard: some View {
        chartCard("學期加權平均走勢", "各學期的學分加權平均分數") {
            Chart(points.filter { $0.gpa != nil }) { p in
                LineMark(x: .value("學期", p.label), y: .value("平均", p.gpa ?? 0))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("學期", p.label), y: .value("平均", p.gpa ?? 0))
                    .foregroundStyle(Theme.accent)
                    .annotation(position: .top) {
                        Text(String(format: "%.1f", p.gpa ?? 0))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: gpaDomain)
            .frame(height: 200)
        }
    }

    private var creditsCard: some View {
        chartCard("各學期取得學分", "每學期通過(及格)課程的學分數") {
            Chart(points) { p in
                BarMark(x: .value("學期", p.label), y: .value("學分", p.credits))
                    .foregroundStyle(Theme.amber)
                    .annotation(position: .top) {
                        if !p.credits.isZero {
                            Text(String(format: "%g", p.credits))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
            }
            .frame(height: 200)
        }
    }

    private var distributionCard: some View {
        chartCard("成績分佈", "所有有分數的課程依區間統計") {
            Chart(distribution) { b in
                BarMark(x: .value("區間", b.label), y: .value("課程數", b.count))
                    .foregroundStyle(b.color)
                    .annotation(position: .top) {
                        if b.count > 0 {
                            Text("\(b.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
            }
            .frame(height: 200)
        }
    }

    // MARK: - Helpers

    /// Pad the GPA axis a little around the actual range so the line isn't flush.
    private var gpaDomain: ClosedRange<Double> {
        let values = points.compactMap(\.gpa)
        guard let lo = values.min(), let hi = values.max() else { return 0...100 }
        let low = max(0, floor((lo - 5) / 10) * 10)
        let high = min(100, ceil((hi + 5) / 10) * 10)
        return low...(high > low ? high : low + 10)
    }

    private func chartCard<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                content().padding(.top, 8)
            }
        }
    }

    private func stat(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
