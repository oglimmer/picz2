import { createApp } from "vue";
import App from "./App.vue";
import router from "./router";
import { useAuth } from "./composables/useAuth";
import "./style.css";

const { initAuth } = useAuth();

function mount(): void {
  createApp(App).use(router).mount("#app");
}

/**
 * A public share link renders for people who have no account here, so it must not sit behind a
 * credential check. `initAuth()` replays whatever `authEmail`/`authPassword` happen to be in
 * localStorage against `/api/auth/check`, and on this route the answer changes nothing that is
 * on screen — the album, its photos and the map are all served from `permitAll` endpoints.
 *
 * <p>So mount straight away here and let the check settle in the background. Protected routes
 * still wait for it: the navigation guard reads `isLoggedIn`, and mounting before it resolves
 * would bounce a signed-in user to the login page on every hard refresh.
 */
const isPublicShareLink = /^\/(app\/)?public\//.test(window.location.pathname);

const authSettled = initAuth();
if (isPublicShareLink) {
  mount();
} else {
  authSettled.finally(mount);
}
