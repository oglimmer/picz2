import {
  createRouter,
  createWebHistory,
  type RouteRecordRaw,
  type NavigationGuardNext,
  type RouteLocationNormalized,
} from "vue-router";
import { useAuth } from "../composables/useAuth";
import LandingView from "../views/LandingView.vue";
import LoginView from "../views/LoginView.vue";
import RegisterView from "../views/RegisterView.vue";
import ForgotPasswordView from "../views/ForgotPasswordView.vue";
import ResetPasswordView from "../views/ResetPasswordView.vue";
import VerificationPendingView from "../views/VerificationPendingView.vue";
import VerifyEmailView from "../views/VerifyEmailView.vue";
import AlbumsView from "../views/AlbumsView.vue";
import GalleryView from "../views/GalleryView.vue";
import PublicGalleryView from "../views/PublicGalleryView.vue";
import ProfileView from "../views/ProfileView.vue";
import ImprintView from "../views/ImprintView.vue";
import PrivacyView from "../views/PrivacyView.vue";
import TermsView from "../views/TermsView.vue";
import SubscriptionConfirmView from "../views/SubscriptionConfirmView.vue";

declare module "vue-router" {
  interface RouteMeta {
    public?: boolean;
    requiresAuth?: boolean;
  }
}

/**
 * Route definitions
 */
const routes: RouteRecordRaw[] = [
  {
    path: "/",
    name: "Home",
    component: LandingView,
    meta: { public: true },
    beforeEnter: (
      _to: RouteLocationNormalized,
      _from: RouteLocationNormalized,
      next: NavigationGuardNext,
    ) => {
      const { isLoggedIn, emailVerified } = useAuth();
      // If logged in and verified, redirect to albums
      if (isLoggedIn.value && emailVerified.value) {
        next("/albums");
      } else {
        next();
      }
    },
  },
  {
    path: "/imprint",
    name: "Imprint",
    component: ImprintView,
    meta: { public: true },
  },
  {
    path: "/privacy",
    name: "Privacy",
    component: PrivacyView,
    meta: { public: true },
  },
  {
    path: "/terms",
    name: "Terms",
    component: TermsView,
    meta: { public: true },
  },
  {
    path: "/login",
    name: "Login",
    component: LoginView,
    meta: { public: true },
    beforeEnter: (
      _to: RouteLocationNormalized,
      _from: RouteLocationNormalized,
      next: NavigationGuardNext,
    ) => {
      const { isLoggedIn, emailVerified } = useAuth();
      // If logged in and verified, redirect to albums
      if (isLoggedIn.value && emailVerified.value) {
        next("/albums");
      } else {
        next();
      }
    },
  },
  {
    path: "/register",
    name: "Register",
    component: RegisterView,
    meta: { public: true },
    beforeEnter: (
      _to: RouteLocationNormalized,
      _from: RouteLocationNormalized,
      next: NavigationGuardNext,
    ) => {
      const { isLoggedIn, emailVerified } = useAuth();
      // If logged in and verified, redirect to albums
      if (isLoggedIn.value && emailVerified.value) {
        next("/albums");
      } else {
        next();
      }
    },
  },
  {
    path: "/forgot-password",
    name: "ForgotPassword",
    component: ForgotPasswordView,
    meta: { public: true },
  },
  {
    path: "/reset-password",
    name: "ResetPassword",
    component: ResetPasswordView,
    meta: { public: true },
  },
  {
    path: "/verification-pending",
    name: "VerificationPending",
    component: VerificationPendingView,
    meta: { public: true },
  },
  {
    path: "/verify-email",
    name: "VerifyEmail",
    component: VerifyEmailView,
    meta: { public: true },
  },
  {
    path: "/public/subscription/confirm",
    name: "SubscriptionConfirm",
    component: SubscriptionConfirmView,
    meta: { public: true },
  },
  {
    path: "/albums",
    name: "Albums",
    component: AlbumsView,
    meta: { requiresAuth: true },
  },
  {
    path: "/profile",
    name: "Profile",
    component: ProfileView,
    meta: { requiresAuth: true },
  },
  {
    path: "/album/:albumId",
    name: "Album",
    component: GalleryView,
    props: true,
    meta: { requiresAuth: true },
  },
  {
    path: "/album/:albumId/presentation",
    name: "AlbumPresentation",
    component: GalleryView,
    props: (route: RouteLocationNormalized) => ({
      albumId: route.params.albumId,
      presentationMode: true,
    }),
    meta: { requiresAuth: true },
  },
  {
    path: "/public/album/:shareToken",
    name: "PublicAlbum",
    component: PublicGalleryView,
    props: true,
    meta: { public: true },
  },
  {
    path: "/public/album/:shareToken/:imageToken",
    name: "PublicImage",
    component: PublicGalleryView,
    props: (route: RouteLocationNormalized) => ({
      shareToken: route.params.shareToken,
      imageToken: route.params.imageToken,
      openLightbox: true,
    }),
    meta: { public: true },
  },
  // App routes (used after redirect from OG page)
  {
    path: "/app/public/album/:shareToken",
    name: "AppPublicAlbum",
    component: PublicGalleryView,
    props: true,
    meta: { public: true },
  },
  {
    path: "/app/public/album/:shareToken/:imageToken",
    name: "AppPublicImage",
    component: PublicGalleryView,
    props: (route: RouteLocationNormalized) => ({
      shareToken: route.params.shareToken,
      imageToken: route.params.imageToken,
      openLightbox: true,
    }),
    meta: { public: true },
  },
];

/**
 * Create router instance
 */
const router = createRouter({
  history: createWebHistory(),
  routes,
});

/**
 * Navigation guard for authentication
 */
router.beforeEach(
  (
    to: RouteLocationNormalized,
    _from: RouteLocationNormalized,
    next: NavigationGuardNext,
  ) => {
    const { isLoggedIn, emailVerified } = useAuth();

    // Public routes don't require authentication
    if (to.meta.public) {
      next();
      return;
    }

    // Protected routes require authentication
    if (to.meta.requiresAuth && !isLoggedIn.value) {
      // Redirect to login with the original destination
      next({
        name: "Login",
        query: { redirect: to.fullPath },
      });
      return;
    }

    // If logged in but email not verified, and trying to access protected route
    // redirect to verification page
    if (
      to.meta.requiresAuth &&
      isLoggedIn.value &&
      !emailVerified.value
    ) {
      next({ name: "VerificationPending" });
      return;
    }

    next();
  },
);

export default router;
