# Dotfiles: zsh + oh-my-zsh
# Generado/actualizado por install.sh (módulo Shell)

# Path (añadido también por install.sh)
export PATH="$HOME/.local/bin:$PATH"

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"

# Opcional: pyenv (si instalas módulo Python)
# [[ -d ~/.pyenv ]] && export PYENV_ROOT="$HOME/.pyenv" && command -v pyenv >/dev/null && eval "$(pyenv init -)"

# Opcional: nvm (si instalas módulo Node)
# export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
