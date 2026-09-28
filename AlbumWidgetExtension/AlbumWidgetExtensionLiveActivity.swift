//
//  AlbumWidgetExtensionLiveActivity.swift
//  AlbumWidgetExtension
//
//  Created by Nadila Rizky Amelia on 22/09/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AlbumWidgetExtensionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct AlbumWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlbumWidgetExtensionAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension AlbumWidgetExtensionAttributes {
    fileprivate static var preview: AlbumWidgetExtensionAttributes {
        AlbumWidgetExtensionAttributes(name: "World")
    }
}

extension AlbumWidgetExtensionAttributes.ContentState {
    fileprivate static var smiley: AlbumWidgetExtensionAttributes.ContentState {
        AlbumWidgetExtensionAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: AlbumWidgetExtensionAttributes.ContentState {
         AlbumWidgetExtensionAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: AlbumWidgetExtensionAttributes.preview) {
   AlbumWidgetExtensionLiveActivity()
} contentStates: {
    AlbumWidgetExtensionAttributes.ContentState.smiley
    AlbumWidgetExtensionAttributes.ContentState.starEyes
}
