//
//  DragToSelectModifier.swift
//  dropTo
//

import SwiftUI
import Combine

//============================================================================
// SHARED STATE: DRAG TO SELECT
//============================================================================
// SHARED STATE UNTUK TRACKING DRAG SESSION GLOBAL ACROSS ALL PHOTOS

class DragToSelectState: ObservableObject {
    static let shared = DragToSelectState()
    
    @Published var isDragging = false
    @Published var shouldSelect = true
    @Published var processedItems: Set<String> = []
    
    func reset() {
        isDragging = false
        processedItems.removeAll()
    }
    
    func startDragging(shouldSelect: Bool) {
        self.isDragging = true
        self.shouldSelect = shouldSelect
        self.processedItems.removeAll()
    }
}

//============================================================================
// VIEW MODIFIER: DRAG TO SELECT
//============================================================================
// MODIFIER INI MEMUNGKINKAN USER UNTUK DRAG GESTUR DI ATAS FOTO-FOTO
// DAN OTOMATIS SELECT/DESELECT FOTO YANG DILEWATI (SMOOTH SEPERTI APPLE PHOTOS)

struct DragToSelectModifier: ViewModifier {
    
    @Binding var isSelecting: Bool
    @Binding var selectedIdentifiers: Set<String>
    let identifier: String
    
    @StateObject private var dragState = DragToSelectState.shared
    @GestureState private var dragLocation: CGPoint?
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .updating($dragLocation) { value, state, _ in
                                    guard isSelecting else { return }
                                    state = value.location
                                }
                                .onChanged { value in
                                    guard isSelecting else { return }
                                    
                                    let frame = geometry.frame(in: .global)
                                    
                                    // START DRAGGING JIKA INI FOTO PERTAMA YANG DI-TAP
                                    if !dragState.isDragging && frame.contains(value.startLocation) {
                                        let shouldSelect = !selectedIdentifiers.contains(identifier)
                                        dragState.startDragging(shouldSelect: shouldSelect)
                                        processItem() // PROSES FOTO PERTAMA
                                    }
                                    
                                    // PROSES ITEM JIKA DRAG LOCATION DI DALAM FRAME
                                    if dragState.isDragging && frame.contains(value.location) {
                                        processItem()
                                    }
                                }
                                .onEnded { _ in
                                    dragState.reset()
                                }
                        )
                        .onChange(of: dragLocation) { _, newLocation in
                            guard isSelecting, dragState.isDragging else { return }
                            
                            if let location = newLocation {
                                let frame = geometry.frame(in: .global)
                                if frame.contains(location) {
                                    processItem()
                                }
                            }
                        }
                }
            )
    }
    
    //============================================================================
    // FUNCTION: PROCESS ITEM
    //============================================================================
    // SELECT/DESELECT FOTO JIKA BELUM PERNAH DIPROSES DALAM DRAG SESSION INI
    
    private func processItem() {
        guard !dragState.processedItems.contains(identifier) else { return }
        
        dragState.processedItems.insert(identifier)
        
        if dragState.shouldSelect {
            if !selectedIdentifiers.contains(identifier) {
                withAnimation(.easeOut(duration: 0.15)) {
                    selectedIdentifiers.insert(identifier)
                }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
            }
        } else {
            if selectedIdentifiers.contains(identifier) {
                withAnimation(.easeOut(duration: 0.15)) {
                    selectedIdentifiers.remove(identifier)
                }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
            }
        }
    }
}

extension View {
    func dragToSelect(
        isSelecting: Binding<Bool>,
        selectedIdentifiers: Binding<Set<String>>,
        identifier: String
    ) -> some View {
        self.modifier(
            DragToSelectModifier(
                isSelecting: isSelecting,
                selectedIdentifiers: selectedIdentifiers,
                identifier: identifier
            )
        )
    }
}
