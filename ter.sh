#!/bin/zsh

if [ ! -d "/var/log/script_logs" ]; then
  mkdir /var/log/script_logs
fi

if [ ! -d "/etc/script_resources" ]; then
  sudo mkdir /etc/script_resources
  sudo chown root:wheel /etc/script_resources
  sudo chmod 744 /etc/script_resources
fi

#DEFINE a funtion that installs the Cask
install_cask() {
    local item=$1
    ConsoleUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')

    #architecture check and setting the correct path for brew
    architecture_type="$(uname -m)"
    if [[ "$architecture_type" == "x86_64" ]]; then
        brew_path="/usr/local/bin/brew"
    else
        brew_path="/opt/homebrew/bin/brew"
    fi

    #check if the app exists, if not install it
    if [[ $(sudo -H -iu $ConsoleUser $brew_path list --casks 2>/dev/null | grep -c ${item}) == "1" ]]; then
        echo "${item} is already installed" >> /var/log/script_logs/brew_install.log
    else
        echo "Performing installation of ${item}"
        sudo -H -iu $ConsoleUser $brew_path install --cask ${item} 2>&1 >> /var/log/script_logs/brew_install.log
        if [[ $? -ne 0 ]]; then
            echo "Error occurred while installing ${item} Please contact the IT department."
            exit 1
        fi
    fi
}

#MAIN 

#ckeck if brew is installed
if ! command -v brew > /dev/null; then
  echo "Homebrew is not installed. Please install it from the Self Service Portal before installing casks."
  exit 1
fi

if ! command -v jq > /dev/null; then
  brew install jq
fi

# Attempt to download the file using curl
curl -s -L "https://drive.google.com/uc?export=download&id=183PDRjwr5OFBJypAMYa" -o /etc/script_resources/approved_apps.json
if [[ $? -eq 0 ]]; then
  #light green
  echo "\033[0m\033[32;1mThis is the list of available Apps that can be installed.\nPlease open a ticket with IT if your desired app is not included.\033[0m"
else
  #if curl failed, use wget as alternative
  if ! command -v wget > /dev/null; then
    brew install wget
  fi

  # retry download with wget
  for i in {1..5}; do
    wget -q -O /etc/script_resources/approved_apps.json "https://drive.google.com/uc?export=download&id=183PDRjwr5OFBJypAMYa"
    if [[ $? -eq 0 ]]; then
    #light green
      echo "\033[0m\033[32;1mThis is the list of available Apps that can be installed.\nPlease open a ticket with IT if your desired app is not included.\033[0m"
      break
    else
    #yellow
      echo -e "\033[33m Attempt $i to update the app list has failed, retrying.\033[0m"
      sleep 3
    fi
  done
  # if wget fails after 5 retries, exit with error
  if [[ $i -eq 5 ]]; then
  #red
    echo -e "\033[31mError: Unable to update the app list after 5 retries\033[0m"
    exit 1
  fi
fi
  

# grab the items from the json file
apps=$(jq -r '.apps[].name' /etc/script_resources/approved_apps.json)

# Create an array to store items
approved_apps=()

# Iterate through the items, enumerate and store them in the array
count=1
for app in $apps; do
  approved_apps+=("$count) $app")
  count=$((count + 1))
done

# Echo the enumerated items
for app in "${approved_apps[@]}"; do
  echo "$app"
done

#loop for input validation
while true; do
  read -p "Enter the number of the cask you wish to install: " item_number

  # Check for empty input or input containing multiple words to reduce the risk of an sql-injection and Unix command execution
  if [[ -z "$item_number" || $(echo $item_number | awk '{print NF}') -ne 1 ]]; then
    echo "Invalid input. Please enter a single number between 1 and ${#approved_apps[@]}"
    continue
   #here we can maybe write the invalid inputs to a file and send it to an email for reporting and to see if any user tried anything malicious 
  fi
 
  #check if the user has typed a number
  if ! [[ $item_number =~ ^[0-9]+$ ]]; then
    echo "Invalid input. Please enter a number between 1 and ${#approved_apps[@]}"
    continue
  fi

  #check if the number that the user gave is a valid casket number
  if ! [[ $item_number -le ${#approved_apps[@]} ]]; then
    echo "Invalid input. Please enter a number between 1 and ${#approved_apps[@]}"
    continue
  fi
  break
done

item="$(echo "${approved_apps[item_number-1]}" | sed -E 's/^[0-9]+\)([[:space:]]*)//')"
install_cask "$item"
