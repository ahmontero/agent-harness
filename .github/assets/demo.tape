# VHS Tape for agent-harness demo
# Install VHS: brew install vhs
# Generate GIF & MP4: vhs .github/assets/demo.tape

Output .github/assets/demo.gif
Output .github/assets/demo.mp4

Set Shell "bash"
Set FontSize 15
Set Width 980
Set Height 580
Set Padding 20
Set Theme "Catppuccin Mocha"
Set WindowBar "Colorful"
Set BorderRadius 10
Set TypingSpeed 40ms

# Intro
Type "# ⚡ agent-harness: The Universal Engineering Harness for AI Agents" Sleep 500ms Enter
Sleep 1s

# 1. Doctor Environment & Health Diagnosis
Type "harness doctor" Sleep 400ms Enter
Sleep 2.5s

# 2. Sub-second Workspace Signal Extraction (<0.5s)
Type "harness context --json" Sleep 400ms Enter
Sleep 2s

# 3. Static Landmines Pre-Commit Scanner
Type "harness scan --all" Sleep 400ms Enter
Sleep 2.5s

# 4. Multi-Harness Verification Suite
Type "./setup --verify" Sleep 400ms Enter
Sleep 3s
