#---------- EXPORTS ----------#
# 🐘 Default PHP version (can be overridden with usephp)
export PHP_MAMP_VERSION="php8.1.29"
export PATH="/Applications/MAMP/bin/php/$PHP_MAMP_VERSION/bin:$PATH"

# 🐍 Python path
export PATH="/Library/Frameworks/Python.framework/Versions/3.13/bin:$PATH"

# 🛢️ MySQL path
export PATH="/usr/local/mysql/bin:$PATH"

# 🍺 Homebrew path
export PATH="/opt/homebrew/bin:$PATH"

export PATH

#---------- ALIASES ----------#
#PHP ARTISAN
alias pa="php artisan"
alias pac="php artisan config:cache"
alias par="php artisan route"
alias parc="php artisan route:cache"
alias parl="php artisan route:list"
alias pam="php artisan migrate"
alias pam:r="php artisan migrate:refresh"
alias pam:roll="php artisan migrate:rollback"
alias pam:rs="php artisan migrate:refresh --seed"
alias pam:s="php artisan migrate --seed"
alias pas="php artisan db:seed"
alias pasc="php artisan db:seed --class="
alias pda="php artisan dumpautoload"

#COMPOSER
alias cu="composer update"
alias ci="composer install"
alias cda="composer dump-autoload -o"

#GIT
alias gl="git log --pretty=format:'%C(yellow)%h\\ %ad%Cred%d\\ %Creset%s%Cblue\\ [%cn]' --decorate --date=short"
alias glg="git log --graph --oneline --decorate --all"

#NPM
alias npmrw="npm run watch"
alias npmrd="npm run dev"
alias npmrp="npm run prod"

#DOTNET
alias dnr="dotnet run"
alias dnb="dotnet build"
alias dnc="dotnet clean"
alias dndu="dotnet ef database update"
alias dndd="dotnet ef database drop"
alias dnma="dotnet ef migrations add"

#PHP
alias currentphp='echo "🐘 PHP version: $PHP_MAMP_VERSION"; php -v'

#---------- FUNCTIONS ----------#
#Switch PHP versions
function usephp() {
  local version=$1
  local new_path="/Applications/MAMP/bin/php/php$version/bin"

  if [ ! -d "$new_path" ]; then
    echo "❌ PHP version $version not found at $new_path"
    return 1
  fi

  # Remove any existing MAMP PHP versions from PATH
  export PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '!/\/Applications\/MAMP\/bin\/php\/php[0-9]+\.[0-9]+\.[0-9]+\/bin/')

  # Add the selected PHP version
  export PATH="$new_path:$PATH"

  # Update the version variable for reference (optional)
  export PHP_MAMP_VERSION="php$version"

  echo "✅ PHP switched to $version"
  echo "📍 which php: $(which php)"
  php -v
}
