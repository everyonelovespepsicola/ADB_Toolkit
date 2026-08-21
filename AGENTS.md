# Agent Project Rules & Directives

## Automatic Git Commits
- **Every Code Change:** After modifying, creating, or deleting any file in this repository, you MUST stage and commit the changes immediately using `git add .` and `git commit`.
- **Detailed Summary:** The git commit message MUST include a detailed, descriptive summary of what was added, modified, or fixed.
  - Example format:
    ```bash
    git commit -m "feat(p2p): update socket engine chunking logic

    - Added 64KB chunk buffer size for image transfers
    - Fixed fallback trigger to relay server on timeout
    - Updated error handling for socket disconnects"
    ```

## Background Script Monitoring & Log Tails
- **Background Tasks:** Whenever you launch a background script, process, or long-running command (using `run_command` async or background tasks), you MUST display the exact PowerShell tail log command in your chat response so the user can follow along live.
- Example snippet to print in chat response:
  ```powershell
  Get-Content -Path "<path_to_log_file>" -Wait -Tail 20
  ```
