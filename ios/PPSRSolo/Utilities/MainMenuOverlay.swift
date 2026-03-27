import SwiftUI

struct MainMenuOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) { MainMenuButton() }
    }
}

extension View {
    func withMainMenuButton() -> some View {
        modifier(MainMenuOverlayModifier())
    }
}

struct PPSRCardNavigationModifier: ViewModifier {
    let cards: [PPSRCard]
    let vm: PPSRAutomationViewModel

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: String.self) { cardId in
                if let card = cards.first(where: { $0.id == cardId }) {
                    PPSRCardDetailView(card: card, vm: vm)
                }
            }
    }
}

struct PPSRCardNavigationWithSelectionModifier: ViewModifier {
    let cards: [PPSRCard]
    let vm: PPSRAutomationViewModel
    @Binding var selectedCardId: String?

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: String.self) { cardId in
                if let card = cards.first(where: { $0.id == cardId }) {
                    PPSRCardDetailView(card: card, vm: vm)
                }
            }
    }
}

extension View {
    func withPPSRCardNavigation(cards: [PPSRCard], vm: PPSRAutomationViewModel) -> some View {
        modifier(PPSRCardNavigationModifier(cards: cards, vm: vm))
    }

    func withPPSRCardNavigation(cards: [PPSRCard], vm: PPSRAutomationViewModel, selectedCardId: Binding<String?>) -> some View {
        modifier(PPSRCardNavigationWithSelectionModifier(cards: cards, vm: vm, selectedCardId: selectedCardId))
    }
}
