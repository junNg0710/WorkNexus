extension DialogCenter {
    /// A dialog is on screen (Esc then belongs to it, not to the panels behind).
    public var isPresenting: Bool { !stack.isEmpty }
}
