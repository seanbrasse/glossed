/// Entry point: call once at app launch.
public enum DesignSystem {
    public static func bootstrap() {
        Typography.registerFonts()
    }
}
