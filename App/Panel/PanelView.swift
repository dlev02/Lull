import SwiftUI

/// The whole panel: a scrolling column of cards.
struct PanelView: View {
  @Environment(AppModel.self) private var model
  @AppStorage("showsMoreSettings") private var showsMoreSettings = false

  var body: some View {
    GeometryReader { geometry in
      ScrollViewReader { proxy in
        ScrollView {
          // One container for every card: the cards share a single glass pass, which
          // keeps scrolling smooth. Zero spacing stops neighbouring cards reaching
          // for each other.
          GlassEffectContainer(spacing: 0) {
            VStack(spacing: 12) {
              Color.clear.frame(height: 0).id("top")
              if model.isIntroVisible {
                IntroCard()
                  .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
              }
              HStack(spacing: 10) {
                CurrentAppCard()
                PowerButton()
              }
              ModeCard()
              LookCard()
              AppGroupsCard()

              Button(showsMoreSettings ? "Less settings" : "More settings") {
                withAnimation(.smooth(duration: 0.35)) {
                  showsMoreSettings.toggle()
                }
              }
              .buttonStyle(.glass)
              .buttonBorderShape(.capsule)
              .padding(.vertical, 2)

              if showsMoreSettings {
                Group {
                  FocusSettingsCard().id("focus")
                  GesturesCard().id("gestures")
                  ShortcutsCard().id("shortcuts")
                  FinishCard().id("finish")
                  IgnoredAppsCard().id("ignored")
                  AboutCard().id("about")
                  FooterCard().id("footer")
                }
                .transition(.opacity)
              }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .animation(.smooth(duration: 0.3), value: model.isIntroVisible)
          }
          // The space between and below the cards belongs to the panel: scrolling
          // works there, and a click there closes it.
          .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
          .background {
            Color.clear
              .contentShape(.rect)
              .onTapGesture {
                model.closePanel?()
              }
          }
        }
        .scrollIndicators(.never)
        .onChange(of: model.scrollTarget) { _, target in
          guard let target else { return }
          if target != "top" {
            showsMoreSettings = true
          }
          withAnimation(.smooth) {
            proxy.scrollTo(target, anchor: .top)
          }
          model.scrollTarget = nil
        }
      }
    }
    .frame(width: PanelController.width)
  }
}
