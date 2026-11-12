# Pasted and dropped files and images go with the message as paths

Decided: 2026-11-12
Status: accepted

The paperclip, ⌘V with files or an image on the clipboard, and a drop on the chat add files as chips under the message box; each chip has a remove button.
A pasted image is saved as a PNG under the temporary `echo-pastes` folder.
Sending types the text, then each file's quoted path, as a drop into the terminal does; Claude Code reads the file from its path.
Text on the clipboard always pastes as text, even when an image is there too.
Why: the paths are what the terminal drop already sends, so the agent needs nothing new and Echo Remote can send the same.
Rejected: uploading file contents through the daemon, which duplicates what the agent can already read from disk.
