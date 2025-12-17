# Photo Upload Gallery - Vue.js Frontend

A beautiful Vue.js application to display all photos uploaded via the Photo Upload Server.

## Features

- 📸 Beautiful responsive photo gallery
- 🔄 Refresh button to load new photos
- 📊 Display photo count and total size
- 🖼️ Lightbox view for full-size images
- ⚡ Fast and modern Vue 3 + Vite setup
- 🎨 Gradient background with smooth animations

## Quick Start

### 1. Install Dependencies

```bash
cd frontend
npm install
```

### 2. Start Development Server

```bash
npm run dev
```

The application will be available at `http://localhost:5173`

### 3. Make sure the backend server is running

```bash
cd ../server
./run.sh
```

The backend should be running on `http://localhost:8080`

## API Configuration

The frontend connects to the backend server at `http://localhost:8080`. If your server runs on a different port, edit `src/App.vue`:

```javascript
apiUrl: "http://localhost:8080"; // Change this to your server URL
```

## Build for Production

```bash
npm run build
```

This will create an optimized build in the `dist/` directory.

To preview the production build:

```bash
npm run preview
```

## Build Metadata

During `npm run build`, a prebuild step generates `public/build-info.json` containing:

- version: from `package.json`
- gitHash: short commit hash
- gitBranch: current branch name
- buildDate: ISO timestamp
- nodeVersion: Node.js version

Vite reads this file to define `__APP_VERSION__` and `__GIT_COMMIT__` at build time, and the JSON is copied to the final `dist/` as `/build-info.json` for runtime inspection.

Run the generator manually if needed:

```bash
npm run prebuild
```

## API Endpoints Used

- `GET /files` - Fetches list of all uploaded files
- `GET /files/:filename` - Serves individual image files

## Project Structure

```
frontend/
├── index.html          # Entry HTML file
├── src/
│   ├── main.js        # App initialization
│   ├── App.vue        # Main component
│   └── style.css      # Global styles
├── package.json       # Dependencies
└── vite.config.js     # Vite configuration
```

## Technologies Used

- **Vue 3** - Progressive JavaScript framework
- **Vite** - Next generation frontend tooling
- **Native Fetch API** - For REST API calls
- **CSS Grid** - Responsive gallery layout

## Features in Detail

### Photo Gallery

- Responsive grid layout that adapts to screen size
- Hover effects with smooth transitions
- Click any photo to view full size

### Stats Display

- Shows total number of photos
- Displays total storage used
- Auto-updates when refreshed

### Lightbox

- Click any photo to view full size
- Click anywhere to close
- Smooth fade-in animation

### Error Handling

- Clear error messages if server is unavailable
- Loading states during data fetch
- Empty state message when no photos exist
