# dropTo 📸

dropTo is a photo organization app that simplifies organizing photos with intuitive drag-and-drop interactions. Instead of manually creating albums and moving photos one by one, users can quickly sort, compare, and manage their photos while keeping everything organized in one place.

---

## Problem

People often accumulate thousands of photos on their devices, making it difficult to organize memories into meaningful collections. Existing gallery apps require multiple taps and menus to move photos into albums, making the process slow and repetitive.

## Solution

dropTo introduces a drag-and-drop workflow that allows users to quickly organize photos into custom albums. The app also provides photo comparison, favorites, and camera integration to create a faster and more intuitive photo management experience.

---

## Features

- **Drag & Drop Organization** — organize photos by dragging them directly into custom albums.
- **Custom Albums** — create, delete, and manage photo albums.
- **Compare Photos** — compare two photos side by side with pinch-to-zoom support.
- **Favorites** — mark important photos inside each album.
- **Calendar View** — browse and organize photos by capture date.
- **Camera Integration** — capture photos and videos directly from the app.
- **Photo Viewer** — view images and videos with zoom, swipe, and delete actions.
- **Undo Action** — restore the most recently organized photo.

---

## Screenshots

<p align="center">
  <img src="screenshots/home.png" width="220"/>
  <img src="screenshots/album-detail.png" width="220"/>
  <img src="screenshots/compare.png" width="220"/>
  <img src="screenshots/photo-viewer.png" width="220"/>
</p>

| Home | Album Detail | Compare | Photo Viewer |
|------|--------------|----------|--------------|
| Organize photos with drag & drop | Manage custom albums | Compare photos side by side | Browse photos and videos |

---

## Tech Stack

- **Swift** — application logic
- **SwiftUI** — declarative user interface
- **PhotoKit (Photos Framework)** — access and manage photos and videos from the user's photo library
- **Combine** — reactive state management with `ObservableObject` and `@Published`
- **UserDefaults + Codable** — local persistence for albums and app state
- **AVKit** — video playback
- **UIKit** (`UIImagePickerController`) — camera integration for capturing photos and videos

---

## Project Structure

```
CH2/
├── AlbumView.swift              → Main drag & drop interface
├── AlbumDetailView.swift        → Album management
├── AlbumCoverView.swift         → Album thumbnail
├── AlbumStore.swift             → Album state management & persistence
├── PhotoLibraryManager.swift    → Photo library access (PhotoKit)
├── CameraView.swift             → Camera integration
├── CompareView.swift            → Photo comparison
├── ShowPicture.swift            → Photo & video viewer
├── ItemModel.swift              → Data models
├── Assets.xcassets
└── CH2App.swift
```

---

## Getting Started

1. Clone this repository.

```bash
git clone https://github.com/nadilarizky05/dropTo.git
```

2. Open `CH2.xcodeproj` in Xcode.

3. Build and run on an iPhone or Simulator (⌘R).

4. Grant Photos and Camera permissions when prompted.

---

## Requirements

- Xcode 16+
- iOS 18+
- Swift 6

---

## Future Improvements

- iCloud synchronization
- Smart album suggestions
- AI-powered photo categorization
- Duplicate photo detection
- Search by object or location

---

## Author

Made by [Nadila Rizky Amelia] (https://github.com/nadilarizky05) and [Az Zahra Azizah Hanum] (https://github.com/azhanumm) (Learner at Apple Developer Academy Bali)
