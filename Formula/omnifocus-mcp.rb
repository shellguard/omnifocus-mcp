class OmnifocusMcp < Formula
  desc "MCP server and CLI for OmniFocus on macOS"
  homepage "https://github.com/shellguard/omnifocus-mcp"
  url "https://github.com/shellguard/omnifocus-mcp/releases/download/v0.3.1/omnifocus-mcp-0.3.1-macos-universal.tar.gz"
  sha256 "ca4a59f9ff547c47ff8e3fae50885f0f52d24f502d4f59fc1364f0b105a28c89"
  license "MIT"
  version "0.3.1"

  depends_on :macos

  def install
    bin.install "omnifocus-mcp"
    bin.install "omnifocus-cli"
  end

  def caveats
    <<~EOS
      Grant automation permission on first run:
        System Settings > Privacy & Security > Automation
        Allow your terminal to control OmniFocus.

      In OmniFocus, enable:
        Automation > Accept scripts from external applications

      MCP server config (Claude Desktop / Claude Code):
        {
          "mcpServers": {
            "omnifocus": {
              "command": "#{bin}/omnifocus-mcp",
              "args": []
            }
          }
        }

      CLI daemon (faster repeated calls):
        omnifocus-cli --install   # auto-start at login
    EOS
  end

  test do
    output = shell_output("#{bin}/omnifocus-cli --help")
    assert_match "Usage: omnifocus-cli", output
    assert_match "list-tasks", output

    # MCP protocol test
    input = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    output = pipe_output("#{bin}/omnifocus-mcp", input)
    assert_match '"protocolVersion"', output
  end
end
