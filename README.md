# Student Marksheet System

A Flutter-based web application for managing and viewing student marksheets with Firebase integration.

## Features

- 🔐 Secure authentication system
- 📊 Upload and process marksheets in CSV/Excel format
- 🔍 Search students by roll number and name
- 📈 Calculate percentage and grades automatically
- 🎯 Customizable passing marks
- 📱 Responsive design for all devices
- 🌈 Modern and intuitive user interface

## Screenshots

### Login Screen
![Login Screen](screenshots/login_screen.png)

### Dashboard Screen
![Dashboard Screen](screenshots/dashboard_screen.png)

### Search Results
![Search Results](screenshots/search_results.png)

## Prerequisites

- Flutter SDK (latest version)
- Firebase account
- Web browser (Chrome recommended)

## Firebase Setup

1. Create a new Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Enable Authentication (Email/Password)
3. Create a Realtime Database
4. Update the Firebase configuration in `lib/main.dart` with your project details:

```dart
await Firebase.initializeApp(
  options: const FirebaseOptions(
    apiKey: "YOUR_API_KEY",
    authDomain: "YOUR_AUTH_DOMAIN",
    databaseURL: "YOUR_DATABASE_URL",
    projectId: "YOUR_PROJECT_ID",
    storageBucket: "YOUR_STORAGE_BUCKET",
    messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
    appId: "YOUR_APP_ID",
    measurementId: "YOUR_MEASUREMENT_ID",
  ),
);
```

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/marksheet-project.git
```

2. Navigate to the project directory:
```bash
cd marksheet-project
```

3. Install dependencies:
```bash
flutter pub get
```

4. Run the application:
```bash
flutter run -d chrome
```

## Usage

### Login
1. Enter your email and password
2. Click the Login button

### Dashboard
1. Enter roll number and optional name to search
2. Set passing marks (default: 35)
3. Click Search to view results
4. Use Upload Marksheet button to add new records

### Uploading Marksheets
1. Prepare your marksheet in CSV or Excel format
2. Click Upload Marksheet
3. Select your file
4. The system will process and store the data automatically

## File Format Requirements

### CSV Format
- First row should contain headers
- First column must be Roll Number
- Required columns: Name, Age, Gender, Class, Section
- Additional columns for subject marks

### Excel Format
- Same structure as CSV
- First sheet will be processed
- First row should contain headers

## Grading System

- A+: 90% and above
- A: 80% - 89%
- B: 70% - 79%
- C: 60% - 69%
- D: 50% - 59%
- F: Below 50% or any subject below passing marks

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support, email your-email@example.com or open an issue in the repository.

## Acknowledgments

- Flutter team for the amazing framework
- Firebase for backend services
- All contributors who have helped improve this project
