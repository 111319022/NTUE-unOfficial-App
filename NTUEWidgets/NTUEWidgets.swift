import WidgetKit
import SwiftUI

/// 下一節課 — systemSmall + the Lock Screen accessory families.
struct NextClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextClassWidget", provider: ClassProvider()) { entry in
            NextClassView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("下一節課")
        .description("顯示上課中或下一節課與下課／上課倒數。")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// 待繳作業 — systemSmall + a Lock Screen rectangular.
struct AssignmentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AssignmentsWidget", provider: ClassProvider()) { entry in
            AssignmentsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("待繳作業")
        .description("顯示最近幾項尚未繳交的作業。")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

/// 課＋作業 — one medium widget that shows both at once.
struct CombinedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CombinedWidget", provider: ClassProvider()) { entry in
            CombinedView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("課程與作業")
        .description("一次顯示下一節課與待繳作業。")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct NTUEWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextClassWidget()
        AssignmentsWidget()
        CombinedWidget()
        ClassLiveActivity()
    }
}
