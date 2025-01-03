#!/bin/bash

# Define color codes
INFO='\033[0;36m'  # Cyan
BANNER='\033[0;35m' # Magenta
WARNING='\033[0;33m'
ERROR='\033[0;31m'
SUCCESS='\033[0;32m'
NC='\033[0m' # No Color

# Function to safely exit on errors
exit_on_error() {
    echo -e "${ERROR}Error: $1${NC}"
    exit 1
}

# Prompt for username and password
while true; do
    read -p "Enter the username for remote desktop: " USER
    if [[ "$USER" == "root" ]]; then
        echo -e "${ERROR}Error: 'root' cannot be used as the username. Please choose a different username.${NC}"
    elif [[ "$USER" =~ [^a-zA-Z0-9] ]]; then
        echo -e "${ERROR}Error: Username contains forbidden characters. Only alphanumeric characters are allowed.${NC}"
    else
        break
    fi
done

while true; do
    read -sp "Enter a strong password for $USER: " PASSWORD
    echo
    if [[ ${#PASSWORD} -lt 8 ]]; then
        echo -e "${ERROR}Error: Password must be at least 8 characters long.${NC}"
    elif [[ ! "$PASSWORD" =~ [A-Z] ]]; then
        echo -e "${ERROR}Error: Password must contain at least one uppercase letter.${NC}"
    elif [[ ! "$PASSWORD" =~ [a-z] ]]; then
        echo -e "${ERROR}Error: Password must contain at least one lowercase letter.${NC}"
    elif [[ ! "$PASSWORD" =~ [0-9] ]]; then
        echo -e "${ERROR}Error: Password must contain at least one number.${NC}"
    else
        break
    fi
done

# Hash the password securely
PASSWORD_HASH=$(openssl passwd -6 "$PASSWORD") || exit_on_error "Failed to hash the password."

# Update the system package list
echo -e "${INFO}Updating package list...${NC}"
sudo apt update || exit_on_error "Failed to update package list."

# Install XFCE Desktop
echo -e "${INFO}Installing XFCE Desktop for lower resource usage...${NC}"
sudo apt install -y xfce4 xfce4-goodies || exit_on_error "Failed to install XFCE Desktop."

# Install XRDP
echo -e "${INFO}Installing XRDP for remote desktop...${NC}"
sudo apt install -y xrdp || exit_on_error "Failed to install XRDP."

# Create user securely
echo -e "${INFO}Adding the user $USER...${NC}"
sudo useradd -m -s /bin/bash $USER || exit_on_error "Failed to create user."
echo "$USER:$PASSWORD_HASH" | sudo chpasswd -e || exit_on_error "Failed to set user password."

# Add user to sudo group
echo -e "${INFO}Adding $USER to the sudo group...${NC}"
sudo usermod -aG sudo $USER || exit_on_error "Failed to add $USER to sudo group."

# Configure XRDP to use XFCE desktop
echo -e "${INFO}Configuring XRDP to use XFCE desktop...${NC}"
echo "xfce4-session" > ~/.xsession || exit_on_error "Failed to write to ~/.xsession."
sudo sed -i '/test -x \/etc\/X11\/Xsession && exec \/etc\/X11\/Xsession/,+1c\startxfce4' "/etc/xrdp/startwm.sh" || exit_on_error "Failed to modify startwm.sh."

# Optimize XRDP settings
echo -e "${INFO}Configuring XRDP for lower color depth and resolution...${NC}"
sudo sed -i '/^#xserverbpp=24/s/^#//; s/xserverbpp=24/xserverbpp=16/' /etc/xrdp/xrdp.ini || exit_on_error "Failed to configure color depth."

sudo sed -i '/^max_bpp=/s/=.*/=16/' /etc/xrdp/xrdp.ini || echo 'max_bpp=16' | sudo tee -a /etc/xrdp/xrdp.ini > /dev/null
sudo sed -i '/^xres=/s/=.*/=1280/' /etc/xrdp/xrdp.ini || echo 'xres=1280' | sudo tee -a /etc/xrdp/xrdp.ini > /dev/null
sudo sed -i '/^yres=/s/=.*/=720/' /etc/xrdp/xrdp.ini || echo 'yres=720' | sudo tee -a /etc/xrdp/xrdp.ini > /dev/null

# Restart XRDP service
echo -e "${INFO}Restarting XRDP service...${NC}"
sudo systemctl restart xrdp || exit_on_error "Failed to restart XRDP service."

# Enable XRDP at startup
echo -e "${INFO}Enabling XRDP service at startup...${NC}"
sudo systemctl enable xrdp || exit_on_error "Failed to enable XRDP at startup."

# Install Google Chrome securely
echo -e "${INFO}Installing Google Chrome...${NC}"
sudo apt install -y wget gnupg || exit_on_error "Failed to install dependencies for Chrome."
wget -q -O /usr/share/keyrings/google-chrome.gpg https://dl.google.com/linux/linux_signing_key.pub || exit_on_error "Failed to download Google Chrome signing key."
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
sudo apt update || exit_on_error "Failed to update package list after adding Chrome repository."
sudo apt install -y google-chrome-stable || exit_on_error "Failed to install Google Chrome."

# Configure UFW if installed
if command -v ufw >/dev/null; then
    echo -e "${INFO}UFW is installed. Checking if it is enabled...${NC}"
    if sudo ufw status | grep -q "Status: active"; then
        echo -e "${INFO}Adding a rule to allow traffic on port 3389...${NC}"
        sudo ufw allow 3389/tcp || exit_on_error "Failed to add UFW rule for port 3389."
        echo -e "${SUCCESS}Port 3389 is now allowed through UFW.${NC}"
    else
        echo -e "${WARNING}UFW is installed but not enabled. Skipping rule addition.${NC}"
    fi
else
    echo -e "${INFO}UFW is not installed. Skipping firewall configuration.${NC}"
fi

# Final message
echo -e "${SUCCESS}Installation complete. XFCE Desktop, XRDP, and Chrome browser have been installed.${NC}"
echo -e "${INFO}You can now connect via Remote Desktop with the user $USER.${NC}"
