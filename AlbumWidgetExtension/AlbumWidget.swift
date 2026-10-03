import WidgetKit
import SwiftUI
import UIKit

struct AlbumWidgetEntry: TimelineEntry {
    let date: Date
    let album: PinnedAlbumSnapshot?
    let coverImage: UIImage?
}

struct AlbumWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlbumWidgetEntry {
        AlbumWidgetEntry(date: .now, album: nil, coverImage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (AlbumWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlbumWidgetEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [loadEntry()], policy: .after(next)))
    }

    private func loadEntry() -> AlbumWidgetEntry {
        let album = PinnedAlbumSnapshot.load()
        let cover = album.flatMap { _ in loadCoverImage() }
        print("📌 Widget load: \(album?.title ?? "belum ada album di-pin")")
        return AlbumWidgetEntry(date: .now, album: album, coverImage: cover)
    }

    private func loadCoverImage() -> UIImage? {
        guard let url = WidgetShared.coverImageURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

private enum WidgetColors {
    static let blueTop      = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let blueBottom   = Color(red: 0.38, green: 0.64, blue: 0.98)
    static let folderTop    = Color(red: 0.40, green: 0.66, blue: 1.00)
    static let folderBottom = Color(red: 0.25, green: 0.53, blue: 0.95)
    static let paperPurple  = Color(red: 0.80, green: 0.74, blue: 0.98)
}

struct AlbumWidgetView: View {
    var entry: AlbumWidgetEntry

    var body: some View {
        Group {
            if let album = entry.album, let coverImage = entry.coverImage {
                pinnedCoverView(album: album, coverImage: coverImage)
            } else {
                emptyOrNoCoverView
            }
        }
        .widgetURL(entry.album.map { WidgetShared.cameraURL(for: $0.id) } ?? WidgetShared.homeURL)
    }

    private func pinnedCoverView(album: PinnedAlbumSnapshot, coverImage: UIImage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if let date = album.lastPhotoDate {
                    Text(Self.dateText(date))
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.9)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "camera.fill")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.3), in: Circle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            ZStack {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: UnitPoint(x: 0.5, y: 0.5),
                    endPoint: .bottom
                )
            }
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    private var emptyOrNoCoverView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer(minLength: 6)

            Text(entry.album?.title ?? "No Album Yet")
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(entry.album == nil ? "Pin an album in dropTo" : "Every shot lands here")
                .font(.system(size: 10, weight: .medium))
                .opacity(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)

            Spacer(minLength: 8)

            pill
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            FolderCameraBadge()
                .offset(x: 14, y: 12)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [WidgetColors.blueTop, WidgetColors.blueBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            logo
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("dropTo")
                .font(.system(size: 13, weight: .semibold))
        }
    }

    @ViewBuilder
    private var logo: some View {
        if UIImage(named: "DropToLogo") != nil {
            Image("DropToLogo").resizable().scaledToFit()
        } else {
            Image(systemName: "photo.stack.fill")
                .resizable()
                .scaledToFit()
                .padding(2)
        }
    }

    private var pill: some View {
        HStack(spacing: 5) {
            Image(systemName: entry.album == nil ? "pin" : "camera")
                .font(.system(size: 11, weight: .semibold))
            Text(entry.album == nil ? "Open dropTo" : "Open Camera")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.white.opacity(0.16))
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
        )
    }
}

struct FolderCameraBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(WidgetColors.paperPurple)
                .frame(width: 32, height: 24)
                .rotationEffect(.degrees(-14))
                .offset(x: 0, y: -11)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.95))
                .frame(width: 32, height: 24)
                .rotationEffect(.degrees(-7))
                .offset(x: 2, y: -8)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [WidgetColors.folderTop, WidgetColors.folderBottom],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 32)
                .rotationEffect(.degrees(-8))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

            ZStack {
                Circle().fill(.white)
                Circle().fill(Color(white: 0.12)).padding(2)
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.45), Color(white: 0.2)],
                                         center: .center, startRadius: 0, endRadius: 7))
                    .padding(7)
                Circle().fill(Color(white: 0.3)).padding(10)
            }
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .offset(x: 13, y: 9)
        }
        .frame(width: 58, height: 52)
    }
}

struct AlbumWidget: Widget {
    let kind: String = WidgetShared.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AlbumWidgetProvider()) { entry in
            AlbumWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Camera")
        .description("Tap to open camera in your pinned album")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    AlbumWidget()
} timeline: {
    AlbumWidgetEntry(date: .now, album: PinnedAlbumSnapshot(id: UUID(), title: "Academy Life", photoCount: 3), coverImage: nil)
    AlbumWidgetEntry(date: .now, album: nil, coverImage: nil)
}
