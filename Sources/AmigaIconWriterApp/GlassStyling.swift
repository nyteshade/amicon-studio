#if os(macOS)
import SwiftUI

// Liquid Glass adoption, gated twice so it's inert anywhere without the macOS 26
// SDK: `#if compiler(>=6.2)` (the Swift that ships with Xcode 26) keeps the new
// symbols out of older toolchains entirely, and `if #available(macOS 26, *)`
// guards them at runtime. On anything older these are no-ops, so the app still
// builds and looks correct (standard materials).
extension View {
    /// Applies the Liquid Glass button style to contained buttons (macOS 26+).
    @ViewBuilder func glassButtons() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { self.buttonStyle(.glass) } else { self }
        #else
        self
        #endif
    }

    /// Wraps the view in a floating Liquid Glass bar (macOS 26+).
    @ViewBuilder func glassBar() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { self.padding(8).glassEffect() } else { self }
        #else
        self
        #endif
    }
}
#endif
