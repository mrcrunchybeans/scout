#!/bin/bash

echo "Setting up Flutter development environment..."

# Install Flutter dependencies
sudo apt-get update
sudo apt-get install -y curl git unzip xz-utils zip libglu1-mesa

# Install Flutter
cd /tmp
git clone https://github.com/flutter/flutter.git -b stable --depth 1
sudo mv flutter /usr/local/flutter
export PATH="$PATH:/usr/local/flutter/bin"
echo 'export PATH="$PATH:/usr/local/flutter/bin"' >> ~/.bashrc

# Enable web support
flutter config --enable-web

# Run flutter doctor
flutter doctor

# Install Firebase CLI
npm install -g firebase-tools

# Navigate to project and get dependencies
cd /workspaces/scout/scout
flutter pub get

echo "✅ Setup complete! Run 'flutter doctor' to verify installation."
