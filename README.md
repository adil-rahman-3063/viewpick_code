# ViewPick 🎬

**ViewPick** is a modern, interactive movie and TV show discovery platform built with Flutter. Originally a mobile app, it has been fully rebuilt and optimized as a truly responsive Web Application (PWA). It reimagines how you find your next watch by combining a Tinder-style swipe interface with smart, personalized recommendations.

🌐 **Live Web Version:** [https://adil-rahman-3063.github.io/viewpick/](https://adil-rahman-3063.github.io/viewpick/)

## ✨ Features

*   **Fully Responsive Layout:** Flawlessly transitions between a sleek desktop sidebar and a convenient mobile bottom navigation bar depending on your screen size.
*   **Swipe to Discover:** Effortlessly browse through movies and TV shows. Swipe **Right** to like (and add to watchlist), **Left** to dislike. The feed continuously learns and loads new cards seamlessly.
*   **Smart Recommendations:** The algorithm learns from your likes and dislikes to suggest content tailored to your taste.
    *   **Strict Language Preferences:** Cycles through your preferred languages to ensure you see content you can understand.
    *   **Genre-Based Suggestions:** Prioritizes genres you've liked in the past.
*   **Granular Dislike Options:** When you dislike an item, you can specify *why*:
    *   **Genre:** "I don't like Horror movies."
    *   **Language:** "I don't watch French films."
    *   **Year:** "I don't like movies from 1990" or "I don't like anything released before 2000."
*   **Interactive List Management:** 
    *   **Swipe Actions:** Provide immediate feedback (mark watched/remove) with optimistic UI updates.
    *   **Smart Sorting:** Recently interacted items automatically move to the top of your list.
    *   **Continuous Series Tracking:** Seamlessly mark episodes as watched directly from the list or series and regress progress if needed.
*   **Performance Optimized:** 
    *   **Smart Caching:** Home Page and Watchlist utilize local caching for instant load times, serving data immediately while syncing in the background.
    *   **Debounced Sync:** User actions are instantly reflected locally while database updates are efficiently batched.
*   **Comprehensive Details:** View trailers, cast & crew, plot summaries, and find out where to stream (Watch Providers).
*   **Explore & Search:** Robust search with specific handling for Movies, Series, and **Actors**.

## 🛠️ Tech Stack

*   **Frontend:** [Flutter Web](https://flutter.dev/) (Dart)
*   **Backend / Database:** [Supabase](https://supabase.com/) (Authentication, Database, Realtime)
*   **Analytics:** Firebase (Configured exclusively for Web)
*   **Data Source:** [TMDB API](https://www.themoviedb.org/) (The Movie Database)

## 🚀 Getting Started

### Prerequisites

*   [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
*   A Supabase project set up.
*   A TMDB API Key.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/adil-rahman-3063/viewpick.git
    cd viewpick
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Environment Setup:**
    Create a `assets/credentials.env` file in the root directory and add your keys:
    ```env
    SUPABASE_URL=your_supabase_url
    SUPABASE_ANON_KEY=your_supabase_anon_key
    ```
    *Note: If you use Firebase Analytics, generate your config via `flutterfire configure --platforms=web`.*

4.  **Run the App locally:**
    ```bash
    flutter run -d chrome
    ```

## 🌐 Web Specifics

*   **Responsive Scaling:** The app relies on device-width viewports to scale naturally on phones, tablets, and desktop monitors. 
*   **HTML Renderer:** Uses CanvasKit or the HTML renderer depending on the build configuration for optimal performance.
*   **PWA Ready:** The app can be installed directly from the browser to the home screen of any device.

## 📱 Install as an App (PWA)

You don't need an app store to install ViewPick! You can install it directly to your home screen for a native, full-screen experience without any lag.

**For iOS (iPhone/iPad):**
1. Open [ViewPick](https://viewpick.vercel.app) in **Safari**.
2. Tap the **Share** button at the bottom of the screen (the square with an arrow pointing up).
3. Scroll down and tap **"Add to Home Screen"**.
4. Tap **Add** in the top right corner. 

**For Android:**
1. Open [ViewPick](https://viewpick.vercel.app) in **Chrome**.
2. A pop-up may automatically appear asking to "Add ViewPick to Home screen". Tap it!
3. If it doesn't appear, tap the **three dots** in the top right corner of Chrome.
4. Tap **"Add to Home screen"** or **"Install app"**.

## ☕ Support the Developer

If you enjoy using ViewPick and want to support its development, consider buying me a coffee! ❤️

**UPI ID:** `adilrahman3063-1@okicici`

<img src="assets/donation.png" width="200" alt="Donation QR Code" />

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
