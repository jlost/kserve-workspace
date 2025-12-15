#!/bin/bash
set +e  # Continue on errors

cd cmd/manager
go get
go install github.com/go-delve/delve/cmd/dlv@latest

COLOR_BLUE="\033[0;94m"
COLOR_GREEN="\033[0;92m"
COLOR_RESET="\033[0m"

# Print useful output for user
echo -e "${COLOR_BLUE}
     %########%
     %###########%       _
         %#########%    | | __ ___   ___  _ __ __   __ ___
         %#########%    | |/ // __| / _ \\\\| '__|\\\\  / // _ \\\\
     %#############%    |   < \\\\__ \\\\|  __/| |    \\\\ V /|  __/
     %#############%    |_|\\\\_\\\\|___/ \\\\___||_|     \\\\_/  \\\\___|
 %###############%
 %###########%${COLOR_RESET}


Welcome to your development container!

This is how you can work with it:
- Files will be synchronized between your local machine and this container
- Some ports will be forwarded, so you can access this container via localhost
- Run \`${COLOR_GREEN}dlv debug --listen=:2345 --headless main.go -- ${COLOR_RESET}\` to start the debugger. The first run will take a while to start.
"

# Set terminal prompt
export PS1="\[${COLOR_BLUE}\]devspace\[${COLOR_RESET}\] ./\W \[${COLOR_BLUE}\]\\$\[${COLOR_RESET}\] "
if [ -z "$BASH" ]; then export PS1="$ "; fi

# Include project's bin/ folder in PATH
export PATH="./bin:$PATH"

# Open shell
bash --norc
