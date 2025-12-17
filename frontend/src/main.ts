import { createApp } from "vue";
import App from "./App.vue";
import router from "./router";
import { useAuth } from "./composables/useAuth";
import "./style.css";

// Initialize auth before mounting the app
const { initAuth } = useAuth();

// Initialize auth and then mount the app
initAuth().finally(() => {
  createApp(App).use(router).mount("#app");
});
