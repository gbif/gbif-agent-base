# Also loaded through BASH_ENV for noninteractive Bash commands.
export NVM_DIR="$HOME/.nvm"
if [ -s /opt/nvm/nvm.sh ]; then
  . /opt/nvm/nvm.sh
fi

# Login shells can reset the image's PATH. Restore toolchains here as well as
# through BASH_ENV, so agent shell commands see the same tools as the entrypoint.
for agent_tool_bin in \
  /opt/cargo/bin \
  /opt/python-bin \
  /usr/local/go/bin \
  "$HOME/go/bin" \
  "$HOME/.cargo/bin" \
  "$HOME/.local/bin" \
  "$HOME/.local/share/gem/bin"; do
  case ":$PATH:" in
    *":$agent_tool_bin:"*) ;;
    *) PATH="$agent_tool_bin:$PATH" ;;
  esac
done
unset agent_tool_bin
export PATH
