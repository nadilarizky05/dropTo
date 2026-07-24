# dropTo — SwiftUI Photo Album App

Hi Dila! 👋 Here's your working code, organized simply since you're new
to Swift. Below is exactly how to get this running in Xcode.

## What this app does

- **Home screen**: a grid of albums (like the Photos app). "All Photos"
  and "Recently Deleted" are pinned at the top, then your custom albums.
- **New Album**: tap the blue "New Album" tile or the `•••` menu →
  give it a title and an optional tag.
- **Inside an album**: empty state says "No photos yet, Take photos or
  drag photos here". Tap the round camera button (bottom-right) →
  opens the real camera → the photo is saved into the iPhone's Photos
  app AND organized into this album automatically, grouped by the day
  it was taken (e.g. "Tue, 01 March").
- **Album cover**: always shows the most recent photo added, just like
  you asked.
- **Single photo view**: tap any thumbnail → opens full-size, keeping
  its real portrait/landscape shape (only grid thumbnails are forced
  into 1:1 squares).
  - **Swipe left** → Delete (haptic buzz + card flies off)
  - **Swipe right** → Keep (moves to next photo)
  - An **"Undo Delete"** button appears for 4 seconds after every delete.
  - Deleted photos go to **Recently Deleted** first — nothing is gone
    for good until you pick "Delete" there.
- **All Photos**: automatically shows every photo already on your
  iPhone — this is the "connect to gallery" part, powered by Apple's
  own Photos framework (called PhotoKit).

## Project structure

```
dropTo/
  dropToApp.swift          → app entry point
  Models/
    AlbumModel.swift        → what an "album" is
  Store/
    AlbumStore.swift         → remembers albums + recently deleted (the "brain")
    PhotoLibraryManager.swift → talks to the iPhone's real Photos library
  Views/
    HomeView.swift            → album grid (first screen)
    NewAlbumSheet.swift        → "Create Album" popup
    AlbumDetailView.swift       → photos inside one album, camera button
    PhotoDetailView.swift        → single photo, swipe to delete/keep
    AllPhotosView.swift           → mirrors your whole photo library
    RecentlyDeletedView.swift      → restore or permanently delete
    AssetThumbnailView.swift        → reusable square thumbnail
    CameraPicker.swift                → wraps the camera so SwiftUI can use it
```

## How to open this in Xcode (step-by-step)

1. Open **Xcode** → **File → New → Project**.
2. Choose **iOS → App**, click Next.
3. Product Name: `dropTo`. Interface: **SwiftUI**. Language: **Swift**.
   Uncheck "Use Core Data" and "Include Tests" (not needed). Click Next,
   pick anywhere to save, click Create.
4. Xcode will make its own `dropToApp.swift` and `ContentView.swift`.
   **Delete both of those** (right-click → Delete → Move to Trash) —
   we're replacing them with the versions in this zip.
5. In Finder, drag the whole `dropTo` folder (with `Models`, `Store`,
   `Views` subfolders) from this zip **into** Xcode's left sidebar,
   inside your project. When the dialog pops up, make sure
   **"Copy items if needed"** is checked and your app target is ticked.
6. Add the permission keys — see `Info-Permissions.plist` in this zip
   for the exact steps (it's just 3 keys added in the target's "Info" tab).
7. Plug in a real iPhone (the Simulator has no real camera or photo
   library to test with properly) → select it as the run destination
   → press the ▶️ Play button.
8. First launch will ask for Photos permission — tap **Allow**.

## A few beginner notes on how it works

- **`@Published` / `ObservableObject`**: think of `AlbumStore` as a
  whiteboard everyone in the app can read. When one screen writes on
  it (e.g. creates an album), every other screen watching it instantly
  updates.
- **PHAsset**: Apple's name for "one photo in the library". dropTo
  never copies your photos — album membership is just a saved list of
  each photo's ID tag (`localIdentifier`).
- **UserDefaults**: a small built-in storage box perfect for saving
  your list of albums so they're still there next time you open the app.
- Feel free to open any file — every one has comments explaining what
  each part does.

Good luck, and enjoy building your Apple Developer Academy portfolio piece! 🍎
