#if DEBUG
// TIJDELIJK (pakket 1 tot pakket 3): de voorbeelden in `Pages/Tabs/TabPreviews.swift` noemen de oude tabs. Die tabs bestaan niet
// meer (`AppTab` is home, library, search); deze namen wijzen naar de nieuwe zodat de oude voorbeelden blijven compileren zonder
// dat een bestand van pakket 3 wordt aangeraakt. Pakket 3 verwijdert `Pages/Tabs/` en dit bestand tegelijk.
extension AppTab {
    static var overview: AppTab { .home }
    static var month: AppTab { .library }
    static var saving: AppTab { .library }
    static var planning: AppTab { .library }
}
#endif
