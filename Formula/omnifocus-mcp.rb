class OmnifocusMcp < Formula
  desc "MCP server and CLI for OmniFocus on macOS"
  homepage "https://github.com/shellguard/omnifocus-mcp"
  url "https://github.com/shellguard/omnifocus-mcp/releases/download/v0.3.2/omnifocus-mcp-0.3.2-macos-universal.tar.gz"
  sha256 "748fd3c072074d75a61498154eb00df1cb7598084ea7431f2590b3c76c9e62d1"
  license "MIT"
  version "0.3.2"

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
