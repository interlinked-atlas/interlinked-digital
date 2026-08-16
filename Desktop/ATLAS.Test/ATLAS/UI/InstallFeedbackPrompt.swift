import SwiftUI

// Shown 60 seconds after a successful install.
//
// Regular users:  Yes → logs confirmation | No → guided failure flow (step1 → step2 → chat)
// Admin user:     Yes → TITAN MEMORY™ save panel
//                 No  → live diagnostic chat with rule-based engine (zero cost)
struct InstallFeedbackPrompt: View {
    let productName: String
    let steps: [InstallStep]
    let hostsEntries: [String]
    let installLog: String
    var sourceURL: URL? = nil
    var installRecord: InstallRecord? = nil
    var historyStore: HistoryStore? = nil
    let onDismiss: () -> Void

    @State private var phase: Phase = .question
    @State private var failureNote: String = ""
    @State private var titanSaved = false
    @State private var opacity: Double = 0
    @State private var offset: CGFloat = 20

    // Diagnostic chat (admin only)
    @State private var chatMessages: [DiagnosticMessage] = []
    @State private var chatInput: String = ""
    @State private var isTyping = false
    @FocusState private var chatFocused: Bool

    // Guided failure flow (regular users)
    @State private var step1Answer: String = ""
    @State private var step2Answer: String = ""
    @State private var guidedChatMessages: [(sender: String, text: String)] = []
    @State private var guidedChatInput: String = ""
    @State private var guidedOpener: String = ""
    @FocusState private var guidedChatFocused: Bool

    private var isAdmin: Bool { AuthManager.shared.isAdmin }
    private var engine: DiagnosticEngine {
        DiagnosticEngine(steps: steps, installLog: installLog, productName: productName)
    }

    enum Phase {
        case rating         // NEW primary: "How is this working?" (4-option quality rating)
        case question       // original Yes/No question — now unreachable, kept for reference
        case noFeedback     // kept as dead code — No button now goes to guidedStep1
        case adminChat      // admin diagnostic chat
        case titanConfirm
        case guidedStep1    // "What went wrong?" 5-option picker
        case guidedStep2    // follow-up question based on step1
        case guidedChat     // free-text chat with ATLAS
        case done
    }

    var body: some View {
        Group {
            switch phase {
            case .rating:       ratingView
            case .question:     questionView
            case .noFeedback:   noFeedbackView
            case .adminChat:    adminChatView
            case .titanConfirm: titanConfirmView
            case .guidedStep1:  guidedStep1View
            case .guidedStep2:  guidedStep2View
            case .guidedChat:   guidedChatView
            case .done:         doneView
            }
        }
        .frame(width: 320)
        .background(Color(hex: "#0A0D1C"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color(hex: "#3ECFB2").opacity(0.30), Color(hex: "#7090B8").opacity(0.15)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1))
        .shadow(color: Color.black.opacity(0.4), radius: 20, y: 8)
        .opacity(opacity)
        .offset(y: offset)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                opacity = 1; offset = 0
            }
        }
    }

    // MARK: - Rating view (new primary question)

    private var ratingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "Quick check-in")
            Text("How is **\(productName)** working?")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#D8DCF0"))
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            Divider().background(Color(hex: "#1E2132"))
            VStack(spacing: 6) {
                atlasButton("Working perfectly", color: Color(hex: "#3ECFB2"), filled: true) {
                    recordPositiveFeedback(rating: "Working perfectly")
                }
                atlasButton("Mostly working", color: Color(hex: "#5B8DEF"), filled: false) {
                    withAnimation(.spring(response: 0.3)) { phase = .guidedStep1 }
                }
                atlasButton("Having some issues", color: Color(hex: "#F0A030"), filled: false) {
                    withAnimation(.spring(response: 0.3)) { phase = .guidedStep1 }
                }
                atlasButton("Not working at all", color: Color(hex: "#F06060"), filled: false) {
                    if isAdmin {
                        withAnimation(.spring(response: 0.3)) { phase = .adminChat }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { chatFocused = true }
                    } else {
                        withAnimation(.spring(response: 0.3)) { phase = .guidedStep1 }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func recordPositiveFeedback(rating: String) {
        TitanMemory.shared.recordConfirmedSuccess(productName: productName)
        let dedupKey: String
        if let url = sourceURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            dedupKey = "atlas.feedbackSubmitted.pkg.\(url.lastPathComponent).\(size)"
        } else {
            dedupKey = "atlas.feedbackSubmitted.\(productName)"
        }
        UserDefaults.standard.set(true, forKey: dedupKey)
        // Persist feedback submission date on the Library record
        if let rec = installRecord, let store = historyStore {
            Task { @MainActor in store.markFeedbackSubmitted(id: rec.id) }
        }
        // Deferred runtime-path discovery
        if let rec = installRecord, let store = historyStore {
            Task.detached(priority: .background) {
                let newPaths = InstallEngine.discoverPathsCreatedSince(date: rec.date)
                if !newPaths.isEmpty {
                    await MainActor.run {
                        store.updateRuntimePaths(id: rec.id, newPaths: newPaths)
                    }
                }
            }
        }
        if isAdmin {
            withAnimation(.spring(response: 0.3)) { phase = .titanConfirm }
        } else {
            flashDone()
        }
    }

    // MARK: - Question view (primary Yes/No)

    private var questionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "Quick check-in")
            Text("Did ATLAS solve the problem?")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#D8DCF0"))
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            Divider().background(Color(hex: "#1E2132"))
            HStack(spacing: 8) {
                atlasButton("No", color: Color(hex: "#F06060"), filled: false) {
                    if isAdmin {
                        withAnimation(.spring(response: 0.3)) { phase = .adminChat }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { chatFocused = true }
                    } else {
                        withAnimation(.spring(response: 0.3)) { phase = .guidedStep1 }
                    }
                }
                atlasButton("Yes", color: Color(hex: "#3ECFB2"), filled: true) {
                    TitanMemory.shared.recordConfirmedSuccess(productName: productName)
                    let dedupKey: String
                    if let url = sourceURL,
                       let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attrs[.size] as? Int64 {
                        dedupKey = "atlas.feedbackSubmitted.pkg.\(url.lastPathComponent).\(size)"
                    } else {
                        dedupKey = "atlas.feedbackSubmitted.\(productName)"
                    }
                    UserDefaults.standard.set(true, forKey: dedupKey)
                    // Deferred runtime-path discovery
                    if let rec = installRecord, let store = historyStore {
                        Task.detached(priority: .background) {
                            let newPaths = InstallEngine.discoverPathsCreatedSince(date: rec.date)
                            if !newPaths.isEmpty {
                                await MainActor.run {
                                    store.updateRuntimePaths(id: rec.id, newPaths: newPaths)
                                }
                            }
                        }
                    }
                    // Admin: auto-save to TITAN MEMORY™ without requiring manual confirmation
                    if isAdmin {
                        TitanMemory.shared.saveAdminConfirmedPattern(
                            productName: productName,
                            fileName: productName,
                            steps: steps,
                            hostsEntries: hostsEntries,
                            installLog: installLog
                        )
                        titanSaved = true
                    }
                    flashDone()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Regular user: No feedback (dead code — kept for reference)

    private var noFeedbackView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "What went wrong?")
            TextEditor(text: $failureNote)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#D8DCF0"))
                .background(Color(hex: "#111422"))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .frame(height: 70)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            Divider().background(Color(hex: "#1E2132"))
            HStack(spacing: 8) {
                atlasButton("Skip", color: Color(hex: "#696E7C"), filled: false) { flashDone() }
                atlasButton("Send Feedback", color: Color(hex: "#3ECFB2"), filled: true) {
                    sendFailureFeedback()
                    flashDone()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Guided Step 1: "What went wrong?"

    private var guidedStep1View: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "What went wrong?")
            Text("Let us know so we can fix it.")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#7090B8"))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            VStack(spacing: 6) {
                step1Button("Nothing happened")
                step1Button("It started but got stuck")
                step1Button("An error message appeared")
                step1Button("Installed but not showing in my DAW")
                step1Button("Something else →", isSomethingElse: true)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private func step1Button(_ label: String, isSomethingElse: Bool = false) -> some View {
        atlasButton(label, color: Color(hex: "#5B8DEF"), filled: false) {
            step1Answer = label
            if isSomethingElse {
                guidedOpener = "Tell me what happened and I'll help figure it out."
                guidedChatMessages = []
                withAnimation(.spring(response: 0.3)) { phase = .guidedChat }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { guidedChatFocused = true }
            } else {
                withAnimation(.spring(response: 0.3)) { phase = .guidedStep2 }
            }
        }
    }

    // MARK: - Guided Step 2: follow-up question

    @ViewBuilder
    private var guidedStep2View: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "A bit more detail")

            Text(step2Question)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#D8DCF0"))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            VStack(spacing: 6) {
                if step1Answer == "An error message appeared" {
                    // Skip options — go straight to chat
                    Color.clear.frame(height: 0).onAppear {
                        guidedOpener = "What did the error message say? Type it out or describe it."
                        guidedChatMessages = []
                        withAnimation(.spring(response: 0.3)) { phase = .guidedChat }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { guidedChatFocused = true }
                    }
                } else {
                    ForEach(step2Options, id: \.self) { option in
                        step2Button(option)
                    }
                    step2Button("Something else →", isSomethingElse: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private var step2Question: String {
        switch step1Answer {
        case "Nothing happened":
            return "Did anything appear on screen at all?"
        case "It started but got stuck":
            return "Where did it stop?"
        case "An error message appeared":
            return "What did the error say?"
        case "Installed but not showing in my DAW":
            return "Which DAW?"
        default:
            return "Tell us more."
        }
    }

    private var step2Options: [String] {
        switch step1Answer {
        case "Nothing happened":
            return ["No — nothing at all", "A window flashed briefly", "A password prompt appeared", "I'm not sure"]
        case "It started but got stuck":
            return ["Extracting files", "Copying files", "Asking for a password", "Progress bar froze"]
        case "Installed but not showing in my DAW":
            return ["Ableton Live", "Logic Pro", "Pro Tools", "FL Studio / Other"]
        default:
            return []
        }
    }

    private func step2Button(_ label: String, isSomethingElse: Bool = false) -> some View {
        atlasButton(label, color: Color(hex: "#7A9BC0"), filled: false) {
            step2Answer = label
            guidedOpener = smartOpener(step1: step1Answer, step2: label)
            guidedChatMessages = []
            withAnimation(.spring(response: 0.3)) { phase = .guidedChat }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { guidedChatFocused = true }
        }
    }

    private func smartOpener(step1: String, step2: String) -> String {
        switch (step1, step2) {
        case ("Nothing happened", "A password prompt appeared"):
            return "It sounds like a permissions issue. Did you enter your Mac password when prompted, or did the prompt disappear?"
        case ("Nothing happened", "No — nothing at all"):
            return "Nothing at all is unusual — sometimes the installer window opens behind other windows. Did you check your Dock or Cmd-Tab to see if it was running?"
        case ("Nothing happened", "A window flashed briefly"):
            return "A window that flashes and closes usually means the installer crashed right away. Do you remember if any error appeared, even briefly?"
        case ("Nothing happened", "I'm not sure"):
            return "No worries — let's work through it. Did you double-click the installer file, or run it another way?"
        case ("It started but got stuck", "Extracting files"):
            return "Extraction can stall if there's not enough disk space. How much free space do you have on your Mac?"
        case ("It started but got stuck", "Copying files"):
            return "Copying stalls are sometimes caused by permission issues on the destination folder. Did a password prompt appear at any point?"
        case ("It started but got stuck", "Asking for a password"):
            return "The password prompt is normal — it needs your Mac login password (not a plugin password). Did entering it not work, or did the prompt disappear?"
        case ("It started but got stuck", "Progress bar froze"):
            return "How long did you wait before giving up? Sometimes extracting large files takes a minute or two."
        case ("Installed but not showing in my DAW", "Logic Pro"):
            return "After installing, did you scan for new plugins in Logic's Audio Unit Manager? Sometimes Logic needs a rescan."
        case ("Installed but not showing in my DAW", "Ableton Live"):
            return "In Ableton, go to Preferences → Plug-Ins and make sure the VST3 (or VST2) folder is enabled, then click Rescan. Does the plugin folder path look right?"
        case ("Installed but not showing in my DAW", "Pro Tools"):
            return "Pro Tools requires AAX plugins in a specific folder. Did the installer mention AAX format? Some plugins need a separate AAX version."
        case ("Installed but not showing in my DAW", "FL Studio / Other"):
            return "Which DAW are you using? I can give you specific scan steps once I know."
        case (_, "Something else →"):
            return "Tell me what happened and I'll help figure it out."
        default:
            return "Tell me more about what happened and I'll help you get it working."
        }
    }

    // MARK: - Guided Chat (regular users)

    private var guidedChatView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "ATLAS Support", icon: "bubble.left.and.bubble.right.fill", iconColor: Color(hex: "#5B8DEF"))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Opening message
                        guidedChatBubble(text: guidedOpener, isAtlas: true)

                        ForEach(Array(guidedChatMessages.enumerated()), id: \.offset) { idx, msg in
                            guidedChatBubble(text: msg.text, isAtlas: msg.sender == "atlas")
                                .id(idx)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(height: 160)
                .background(Color(hex: "#070A17"))
                .onChange(of: guidedChatMessages.count) { _ in
                    let last = guidedChatMessages.count - 1
                    if last >= 0 {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            Divider().background(Color(hex: "#1E2132"))

            HStack(spacing: 8) {
                TextField("Describe the issue…", text: $guidedChatInput)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#D8DCF0"))
                    .textFieldStyle(.plain)
                    .focused($guidedChatFocused)
                    .onSubmit { sendGuidedChatMessage() }

                Button(action: sendGuidedChatMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(guidedChatInput.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color(hex: "#2A2E40")
                            : Color(hex: "#5B8DEF"))
                }
                .buttonStyle(.plain)
                .disabled(guidedChatInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: "#0D1020"))

            Divider().background(Color(hex: "#1E2132"))

            HStack(spacing: 8) {
                atlasButton("Skip", color: Color(hex: "#696E7C"), filled: false) { flashDone() }
                atlasButton("Send Report", color: Color(hex: "#5B8DEF"), filled: true) {
                    sendGuidedFeedback()
                    flashDone()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func guidedChatBubble(text: String, isAtlas: Bool) -> some View {
        HStack {
            if !isAtlas { Spacer(minLength: 32) }
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(isAtlas ? Color(hex: "#D8DCF0") : Color(hex: "#08090E"))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isAtlas ? Color(hex: "#131629") : Color(hex: "#5B8DEF"))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if isAtlas { Spacer(minLength: 32) }
        }
    }

    private func sendGuidedChatMessage() {
        let text = guidedChatInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guidedChatInput = ""
        guidedChatMessages.append((sender: "user", text: text))

        // Build a DiagnosticMessage history for the engine
        var history: [DiagnosticMessage] = [
            DiagnosticMessage(sender: .atlas, text: guidedOpener)
        ]
        for msg in guidedChatMessages {
            history.append(DiagnosticMessage(
                sender: msg.sender == "user" ? .user : .atlas,
                text: msg.text
            ))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let response = engine.respond(to: text, history: history)
            guidedChatMessages.append((sender: "atlas", text: response))
        }
    }

    private func sendGuidedFeedback() {
        let transcript = guidedChatMessages.map { ["sender": $0.sender, "text": $0.text] }
        let payload: [String: Any] = [
            "step1": step1Answer,
            "step2": step2Answer,
            "chat": transcript,
            "product": productName
        ]
        let json = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // Persist feedback submission date on the Library record
        if let rec = installRecord, let store = historyStore {
            Task { @MainActor in store.markFeedbackSubmitted(id: rec.id) }
        }
        Task {
            guard let token = AuthManager.shared.session?.accessToken else { return }
            try? await SupabaseService.shared.uploadLog(
                accessToken:  token,
                logType:      "install-failure-guided",
                appName:      productName,
                filename:     productName,
                content:      json,
                deviceName:   Host.current().localizedName ?? "Mac",
                hardwareUUID: atlasHardwareUUID()
            )
        }
    }

    // MARK: - Admin diagnostic chat

    private var adminChatView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "ATLAS Diagnostic", icon: "stethoscope", iconColor: Color(hex: "#F0A030"))

            // Chat history
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Opening message from ATLAS
                        if chatMessages.isEmpty {
                            chatBubble(
                                text: "What went wrong with \(productName)? Describe it and I'll help figure it out.",
                                sender: .atlas
                            )
                        }
                        ForEach(chatMessages) { msg in
                            chatBubble(text: msg.text, sender: msg.sender)
                                .id(msg.id)
                        }
                        if isTyping {
                            typingIndicator
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(height: 180)
                .background(Color(hex: "#070A17"))
                .onChange(of: chatMessages.count) { _ in
                    if let last = chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider().background(Color(hex: "#1E2132"))

            // Input row
            HStack(spacing: 8) {
                TextField("Describe the issue…", text: $chatInput)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#D8DCF0"))
                    .textFieldStyle(.plain)
                    .focused($chatFocused)
                    .onSubmit { sendChatMessage() }

                Button(action: sendChatMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(chatInput.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color(hex: "#2A2E40")
                            : Color(hex: "#3ECFB2"))
                }
                .buttonStyle(.plain)
                .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: "#0D1020"))

            Divider().background(Color(hex: "#1E2132"))

            // Bottom actions
            HStack(spacing: 8) {
                atlasButton("Dismiss", color: Color(hex: "#696E7C"), filled: false) { animatedDismiss() }
                atlasButton("Save to TITAN MEMORY™", color: Color(hex: "#A78BFA"), filled: true) {
                    saveTitanWithChatContext()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func sendChatMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        chatInput = ""
        chatMessages.append(DiagnosticMessage(sender: .user, text: text))
        isTyping = true

        // Small delay so it feels like ATLAS is thinking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let response = engine.respond(to: text, history: chatMessages)
            isTyping = false
            chatMessages.append(DiagnosticMessage(sender: .atlas, text: response))
        }
    }

    @ViewBuilder
    private func chatBubble(text: String, sender: DiagnosticMessage.Sender) -> some View {
        HStack {
            if sender == .user { Spacer(minLength: 32) }
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(sender == .atlas ? Color(hex: "#D8DCF0") : Color(hex: "#08090E"))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(sender == .atlas
                    ? Color(hex: "#131629")
                    : Color(hex: "#3ECFB2"))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if sender == .atlas { Spacer(minLength: 32) }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color(hex: "#3ECFB2").opacity(0.5))
                    .frame(width: 5, height: 5)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: isTyping)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "#131629"))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func saveTitanWithChatContext() {
        // Build a combined log: install log + chat transcript
        let transcript = chatMessages.map { m in
            "\(m.sender == .user ? "ADMIN" : "ATLAS"): \(m.text)"
        }.joined(separator: "\n")
        let combinedLog = installLog + "\n\n--- DIAGNOSTIC CHAT ---\n" + transcript

        TitanMemory.shared.saveAdminConfirmedPattern(
            productName: productName,
            fileName: productName,
            steps: steps,
            hostsEntries: hostsEntries,
            installLog: combinedLog
        )
        titanSaved = true
        flashDone()
    }

    // MARK: - TITAN MEMORY™ confirm (after Yes)

    private var titanConfirmView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "TITAN MEMORY™", icon: "brain.fill", iconColor: Color(hex: "#A78BFA"))

            Text("Save this as a confirmed install pattern?")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#D8DCF0"))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(steps.prefix(6).enumerated()), id: \.offset) { i, step in
                        HStack(spacing: 6) {
                            Text("\(i + 1)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#A78BFA"))
                                .frame(width: 14)
                            Image(systemName: step.icon)
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#7090B8"))
                            Text(step.url.lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#8890B0"))
                                .lineLimit(1)
                        }
                    }
                    if steps.count > 6 {
                        Text("+ \(steps.count - 6) more steps")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#50566A"))
                            .padding(.leading, 20)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            if !hostsEntries.isEmpty {
                Text("\(hostsEntries.count) server(s) blocked")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#3ECFB2").opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            Divider().background(Color(hex: "#1E2132"))
            HStack(spacing: 8) {
                atlasButton("Skip", color: Color(hex: "#696E7C"), filled: false) { flashDone() }
                atlasButton("Save to TITAN MEMORY™", color: Color(hex: "#A78BFA"), filled: true) {
                    TitanMemory.shared.saveAdminConfirmedPattern(
                        productName: productName,
                        fileName: productName,
                        steps: steps,
                        hostsEntries: hostsEntries,
                        installLog: installLog
                    )
                    titanSaved = true
                    flashDone()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Done flash

    private var doneView: some View {
        HStack(spacing: 8) {
            Image(systemName: titanSaved ? "brain.fill" : "checkmark.circle.fill")
                .foregroundColor(titanSaved ? Color(hex: "#A78BFA") : Color(hex: "#3ECFB2"))
            Text(titanSaved ? "Saved to TITAN MEMORY™" : "Thanks for the feedback!")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#D8DCF0"))
        }
        .padding(16)
    }

    // MARK: - Shared helpers

    private func header(title: String,
                        icon: String = "checkmark.circle.fill",
                        iconColor: Color = Color(hex: "#3ECFB2")) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(iconColor)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#8890B0"))
            Spacer()
            Button { animatedDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#696E7C"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func atlasButton(_ label: String, color: Color, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: filled ? .semibold : .medium))
                .foregroundColor(filled ? Color(hex: "#08090E") : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(filled ? color : color.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(filled ? nil :
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(color.opacity(0.30), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func flashDone() {
        withAnimation(.spring(response: 0.3)) { phase = .done }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { animatedDismiss() }
    }

    private func animatedDismiss() {
        withAnimation(.easeOut(duration: 0.18)) { opacity = 0; offset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onDismiss() }
    }

    private func sendFailureFeedback() {
        guard !failureNote.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            guard let token = AuthManager.shared.session?.accessToken else { return }
            try? await SupabaseService.shared.uploadLog(
                accessToken:  token,
                logType:      "install-failure-feedback",
                appName:      productName,
                filename:     productName,
                content:      failureNote,
                deviceName:   Host.current().localizedName ?? "Mac",
                hardwareUUID: atlasHardwareUUID()
            )
        }
    }
}
