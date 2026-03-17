# AZL Desktop - Electron Application

A powerful desktop application for managing AZL Language runtime and services, built with Electron.

## 🚀 Features

- **Service Management**: Start/stop AZL runtime, sysproxy, and provider services
- **Health Monitoring**: Real-time health checks and status monitoring
- **Training Dashboard**: Advanced training control and monitoring
- **Process Monitoring**: Automatic process health monitoring and recovery
- **Auto-updates**: Seamless application updates via GitHub releases
- **Cross-platform**: Windows, macOS, and Linux support
- **Accessibility**: Full keyboard navigation and screen reader support
- **Security**: CSP headers, certificate pinning, and sandboxing

## 📋 Requirements

- Node.js 18+ 
- npm 8+ or yarn 1.22+
- Electron 28+
- Linux: GTK3, libnotify, and other dependencies (see build config)

## 🛠️ Development Setup

### Prerequisites

```bash
# Install Node.js dependencies
npm install

# Install development dependencies
npm install --save-dev electron-builder chokidar source-map-support
```

### Environment Variables

```bash
# Development mode
export NODE_ENV=development
export ELECTRON_ENABLE_SOURCE_MAPS=true
export ELECTRON_ENABLE_LOGGING=true
export ELECTRON_AUTO_DEVTOOLS=true

# Optional: Enable Node.js inspector
export ELECTRON_ENABLE_INSPECTOR=true
```

### Development Commands

```bash
# Start development mode
npm run dev

# Start with hot reload
npm run dev:hot

# Build for distribution
npm run dist

# Build for specific platform
npm run dist:linux
npm run dist:win
npm run dist:mac

# Package without building
npm run pack
```

## 🏗️ Project Structure

```
electron/
├── src/                    # Source code
│   ├── error/             # Error handling system
│   ├── security/          # Security manager
│   ├── lifecycle/         # App lifecycle management
│   ├── ui/                # UI components and menu
│   └── dev/               # Development tools
├── build/                 # Build resources
│   ├── icons/             # Application icons
│   ├── entitlements.mac.plist  # macOS entitlements
│   └── installer.nsh      # NSIS installer scripts
├── test/                  # Test files
├── dist/                  # Distribution builds
├── main.js                # Main process entry point
├── preload.js             # Preload script
├── ui.html                # Main UI
├── package.json           # Package configuration
└── electron-builder.yml   # Build configuration
```

## 🔧 Configuration

### Build Configuration

The application uses `electron-builder.yml` for build configuration:

- **Cross-platform builds**: Windows (NSIS, portable), macOS (DMG), Linux (AppImage, DEB, RPM, Snap)
- **Code signing**: Configurable for all platforms
- **Auto-updates**: GitHub releases integration
- **Custom installers**: NSIS scripts and DMG backgrounds

### Security Configuration

- **CSP Headers**: Strict Content Security Policy
- **Certificate Pinning**: For critical domains
- **Sandboxing**: Process isolation and permissions
- **Input Validation**: Path traversal and URL validation

## 🧪 Testing

### Running Tests

```bash
# Run all tests
npm test

# Run tests with coverage
npm run test:coverage

# Run tests in watch mode
npm run test:watch

# Run specific test file
npm test -- --testPathPattern=error-handler.test.js
```

### Test Structure

- **Unit Tests**: Individual component testing
- **Integration Tests**: Component interaction testing
- **E2E Tests**: Full application flow testing
- **Mock Files**: File and module mocking

## 📦 Building and Distribution

### Build Commands

```bash
# Build for current platform
npm run build

# Build for all platforms
npm run build:all

# Build with specific options
npm run build -- --linux --win --mac
```

### Distribution

```bash
# Create installer packages
npm run dist

# Publish to GitHub releases
npm run publish
```

## 🔐 Code Signing

### macOS

```bash
# Set environment variables
export CSC_LINK=/path/to/certificate.p12
export CSC_KEY_PASSWORD=your_password

# Build signed package
npm run dist:mac
```

### Windows

```bash
# Set environment variables
export CSC_LINK=/path/to/certificate.p12
export CSC_KEY_PASSWORD=your_password

# Build signed package
npm run dist:win
```

## 🚀 Deployment

### Auto-updates

The application automatically checks for updates and downloads them in the background. Updates are applied on restart.

### Release Process

1. Update version in `package.json`
2. Create GitHub release with tag
3. Build and sign packages
4. Upload to GitHub releases
5. Application will auto-update

## 🎨 UI Development

### Adding New Features

1. Create UI components in `src/ui/`
2. Add IPC handlers in `main.js`
3. Update preload script for renderer communication
4. Add menu items in `src/ui/menu-manager.js`

### Styling

- CSS variables for theming
- Responsive design with CSS Grid
- Dark/light theme support
- High contrast accessibility mode

## 🔍 Debugging

### Development Mode

- DevTools automatically open
- Hot reload enabled
- Source maps available
- Performance monitoring

### Production Debugging

- Error logging to user data directory
- Crash reporting (configurable)
- Health monitoring and reporting

## 📱 Platform-Specific Features

### Linux

- Systemd service integration
- AppImage packaging
- Snap package support
- Desktop integration

### macOS

- Menu bar integration
- Dock integration
- Spotlight search
- Touch Bar support (if available)

### Windows

- Start menu integration
- Taskbar integration
- Windows notifications
- Auto-startup configuration

## 🚨 Troubleshooting

### Common Issues

1. **Service won't start**: Check systemd status and logs
2. **Build fails**: Verify Node.js version and dependencies
3. **Auto-update fails**: Check GitHub token and permissions
4. **Permission denied**: Check file permissions and user rights

### Logs

- Application logs: `~/.config/AZL Desktop/logs/`
- Error logs: `~/.config/AZL Desktop/logs/errors.log`
- Health reports: `~/.config/AZL Desktop/health/`

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Make changes with tests
4. Submit pull request

### Code Style

- Use ES6+ features
- Follow ESLint configuration
- Add JSDoc comments
- Write unit tests for new features

## 📄 License

ISC License - see LICENSE file for details.

## 🆘 Support

- **Issues**: GitHub Issues
- **Documentation**: This README and inline code comments
- **Community**: GitHub Discussions

## 🔄 Changelog

### v1.0.0
- Initial release
- Basic service management
- Health monitoring
- Cross-platform support
- Auto-updates
- Security features
- Accessibility support
- Development tools
- Comprehensive testing
- Build automation

---

**Built with ❤️ by Abdulrahman Alzalameh**
