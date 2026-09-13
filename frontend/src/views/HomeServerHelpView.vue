<template>
  <div class="legal-container">
    <header class="legal-header">
      <h1 class="legal-title">
        Your photos, at home
      </h1>
      <p class="legal-subtitle">
        Under your own roof — private, independent, and still easy to share with the people
        you choose.
      </p>
    </header>

    <div class="legal-content">
      <section class="help-manifesto">
        <p class="help-manifesto-lead">
          Your photos belong to you. Not to a cloud company.
        </p>
        <p>
          Photos are the most private thing most of us own: our children, our homes, where we
          were and when. With your own server, the files of your albums are stored in your
          home, on a disk you can touch. No cloud company keeps them, looks through them, sets
          the price, changes the rules, or decides one day to close your account. You are not
          locked in to anyone — you can copy your photos away or switch the server off
          whenever you want.
        </p>
        <p>
          Picz only keeps the gallery around them: the albums, their order, captions and
          sharing. When someone you invited opens an album, Picz fetches the pictures from
          your home and passes them on.
        </p>
      </section>

      <p>
        This guide takes you from an empty machine to an album whose photo files live on the
        server in your living room. Plan about an hour. You need to be comfortable with a
        terminal. There are two ways to let Picz reach your server; you choose one below, and
        the guide shows only the steps for that way.
      </p>

      <h2>Why you would do this</h2>
      <ul>
        <li>
          <strong>Privacy.</strong> The photo files are stored in your home, on a disk you own.
          The album still looks and works like any other Picz album.
        </li>
        <li>
          <strong>Independence.</strong> No storage contract to cancel, no price change to
          fear. Your archive is a folder on your own disk.
        </li>
        <li>
          <strong>No limit from us.</strong> What you keep on your own server does not count
          against your space on this site. Your disk is the only limit.
        </li>
        <li>
          <strong>Big family archives.</strong> Years of holiday photos and videos fit on one
          large disk, and you still share albums with a simple link.
        </li>
        <li>
          <strong>It is a nice home-lab project.</strong> If you already run a small server,
          this adds a use for it that the whole family sees.
        </li>
      </ul>

      <h2>How it works</h2>
      <p>
        Picz stays the gallery: albums, order, tags, captions, sharing and the map all live on
        this site. The photo files of an album that uses your server are stored on your server.
        When someone opens the album, Picz fetches the pictures from your server and passes
        them on. Visitors never talk to your server directly, so nothing on it has to be
        public.
      </p>
      <p>Four things follow from that:</p>
      <ul>
        <li>
          <strong>Picz must reach your server over the internet.</strong> An address that
          works only on your home Wi‑Fi is not enough. Steps 3 and 4 show how.
        </li>
        <li>
          <strong>Your server must be switched on.</strong> While it is off, the pictures of
          its albums do not load, and new uploads into those albums can fail.
        </li>
        <li>
          <strong>The choice is made per album, and it is final.</strong> You pick the storage
          when you create an album. It cannot be changed afterwards.
        </li>
        <li>
          <strong>Give Picz a bucket of its own.</strong> Picz tidies up files it does not
          know about in its own folders, so do not keep anything else in that bucket.
        </li>
      </ul>

      <h2 id="choose-your-way">
        Choose your way in
      </h2>
      <p>
        Not sure which one fits? On a FRITZ!Box, open <strong>Internet › Online Monitor</strong>
        (<em>Internet › Online-Monitor</em>). If it shows an IPv4 address, both ways work. If it
        says <strong>DS-Lite</strong>, choose way B.
      </p>
      <div
        class="help-ways"
        role="group"
        aria-label="How Picz reaches your server"
      >
        <button
          type="button"
          class="help-way"
          :class="{ 'is-active': way === 'fritzbox' }"
          :aria-pressed="way === 'fritzbox'"
          @click="chooseWay('fritzbox')"
        >
          <span class="help-way-tag">Way A</span>
          <span class="help-way-title">FRITZ!Box port sharing</span>
          <span class="help-way-text">
            Your connection has its own IPv4 address. Picz connects straight to your home, and
            nobody sits in between. No domain needed.
          </span>
        </button>
        <button
          type="button"
          class="help-way"
          :class="{ 'is-active': way === 'tunnel' }"
          :aria-pressed="way === 'tunnel'"
          @click="chooseWay('tunnel')"
        >
          <span class="help-way-tag">Way B</span>
          <span class="help-way-title">Cloudflare Tunnel</span>
          <span class="help-way-text">
            Works with DS-Lite and any router, with no ports opened. Your server connects out to
            Cloudflare, and Picz reaches it through there. Needs a domain of your own.
          </span>
        </button>
      </div>

      <h2>What you need</h2>
      <ul>
        <li>
          A computer that is always on: a mini PC, a NAS that runs containers, or a single-board
          computer with an SSD. It needs <a
            href="https://docs.docker.com/engine/install/"
            target="_blank"
            rel="noopener"
          >Docker</a> with the Compose plugin.
        </li>
        <li>Enough disk space for your photos and videos, and ideally a second disk for backups.</li>
        <template v-if="way === 'fritzbox'">
          <li>A FRITZ!Box as your internet router, and its password.</li>
          <li>
            An internet connection with a public IPv4 address of its own. Step 3 shows how to
            check this.
          </li>
          <li>
            No domain name is needed: the FRITZ!Box gives you a free address that follows your
            home. If you own a domain, you can use it instead.
          </li>
        </template>
        <template v-else>
          <li>
            A free <a
              href="https://dash.cloudflare.com/sign-up"
              target="_blank"
              rel="noopener"
            >Cloudflare</a> account. The free plan is enough.
          </li>
          <li>
            A domain of your own. Its DNS moves to Cloudflare in step 3, which means changing
            its name servers where you bought the domain.
          </li>
          <li>Any router and any internet connection, DS-Lite included. No port sharing.</li>
        </template>
      </ul>
      <p class="help-note">
        <template v-if="way === 'fritzbox'">
          <code>{{ host }}</code> is an example MyFRITZ! address. Everywhere below, replace it
          with your own address from step 3, and every password with one of your own.
        </template>
        <template v-else>
          <code>{{ host }}</code> stands for an address on your own domain. Everywhere below,
          replace it with yours, and every password with one of your own.
        </template>
      </p>

      <h2>Step 1 — Start MinIO</h2>
      <p>
        <a
          href="https://min.io/docs/minio/container/index.html"
          target="_blank"
          rel="noopener"
        >MinIO</a> is the storage server Picz talks to. On your home server, create a folder, save
        this as <code>compose.yaml</code> in it, and run <code>docker compose up -d</code>.
      </p>
      <pre><code>services:
  minio:
    image: quay.io/minio/minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: change-me-to-a-long-password
    ports:
      - "9000:9000"   # the API — this is what Picz talks to
      - "9001:9001"   # the Console — for you, on your home network only
    volumes:
      - /srv/minio:/data   # where the photo files are kept on disk
    restart: unless-stopped</code></pre>
      <p>
        Port 9000 is the API. Port 9001 is the web Console. Never share port 9000 or 9001 on
        your router; Picz reaches the API only through the way you chose.
      </p>

      <h2>Step 2 — Create a bucket and a key for Picz</h2>
      <p>
        Use <code>mc</code>, MinIO's command-line client. If you do not have it installed, run it
        in Docker on the same machine:
      </p>
      <pre><code>docker run --rm -it --network host -v "$PWD":/work -w /work \
  --entrypoint sh quay.io/minio/mc</code></pre>
      <p>
        First save the rights Picz needs as <code>picz-policy.json</code>. It may list the bucket,
        and read, write and delete in it — nothing else.
      </p>
      <pre><code>{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"],
      "Resource": ["arn:aws:s3:::picz"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject",
                 "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],
      "Resource": ["arn:aws:s3:::picz/*"]
    }
  ]
}</code></pre>
      <p>
        The <code>arn:aws:s3:::</code> part is simply how MinIO writes a bucket name in a policy.
        Then create the bucket, the policy and a user for Picz:
      </p>
      <pre><code>mc alias set home http://localhost:9000 admin 'change-me-to-a-long-password'
mc mb home/picz
mc admin policy create home picz-rw picz-policy.json
mc admin user add home picz 'another-long-password'
mc admin policy attach home picz-rw --user picz</code></pre>
      <p>
        The user name <code>picz</code> is your <strong>access key</strong>, and
        <code>another-long-password</code> is your <strong>secret key</strong>. Write both down;
        you need them in step 5.
      </p>

      <p class="help-way-reminder">
        Steps 3 and 4 are for <strong>{{ way === 'fritzbox' ? 'way A, FRITZ!Box port sharing' : 'way B, Cloudflare Tunnel' }}</strong>.
        <button
          type="button"
          class="help-way-switch"
          @click="chooseWay(way === 'fritzbox' ? 'tunnel' : 'fritzbox')"
        >
          Show {{ way === 'fritzbox' ? 'way B, Cloudflare Tunnel' : 'way A, FRITZ!Box' }} instead
        </button>
      </p>

      <!-- Way A: straight into the home through the FRITZ!Box. -->
      <template v-if="way === 'fritzbox'">
        <h2>Step 3 — Give your home a name that follows its address</h2>
        <p>
          Most home connections get a new public IP address from time to time — after a
          reconnect, a router restart, or simply every night. Picz cannot follow a changing
          number, but it can follow a name. The FRITZ!Box keeps such a name up to date by itself.
        </p>
        <p class="help-menu-hint">
          Open the FRITZ!Box in a browser at <code>http://fritz.box</code>. Menu names are given
          in English, with the German names in brackets. Some menus appear only when
          <strong>View: Advanced</strong> (<em>Ansicht: Erweitert</em>) is switched on at the
          bottom of the page.
        </p>

        <h3>3.1 Check that you have your own IPv4 address</h3>
        <p>
          Open <strong>Internet › Online Monitor</strong> (<em>Internet › Online-Monitor</em>).
          If you see an IPv4 address there, you are fine.
        </p>
        <p class="help-note">
          If it says <strong>DS-Lite</strong>, or shows no IPv4 address, your provider shares one
          IPv4 address among many customers. Then no port sharing over IPv4 can reach your home.
          Ask your internet provider for a public IPv4 address (a “dual stack” connection), or
          <button
            type="button"
            class="help-way-switch"
            @click="chooseWay('tunnel')"
          >
            use way B, the Cloudflare Tunnel
          </button>.
        </p>

        <h3>3.2 Give the home server a fixed place in your home network</h3>
        <p>
          Open <strong>Home Network › Network</strong> (<em>Heimnetz › Netzwerk</em>), edit your
          home server, and tick <strong>Always assign this network device the same IPv4
            address</strong> (<em>Diesem Netzwerkgerät immer die gleiche IPv4-Adresse
            zuweisen</em>). Otherwise the port sharing in step 4 can point at an empty address
          after a restart.
        </p>

        <h3>3.3 Get a name for your home</h3>
        <p>
          <strong>The simple way: MyFRITZ!.</strong> Open <strong>Internet › MyFRITZ! Account</strong>
          (<em>Internet › MyFRITZ!-Konto</em>), register with your e-mail address, and confirm
          the e-mail you receive. The FRITZ!Box then shows your permanent address, which looks
          like <code>{{ host }}</code>. It always points at your current home address, whenever
          that changes. This is your name — the rest of this guide uses the example, so put
          your own address wherever it appears.
        </p>
        <p>
          <strong>With your own domain.</strong> Open <strong>Internet › Permit Access ›
            DynDNS</strong> (<em>Internet › Freigaben › DynDNS</em>), tick <strong>Use
            DynDNS</strong>, choose <strong>User-defined</strong> as the provider, and enter the
          update URL, your domain name, user name and password. The company that runs the DNS
          of your domain lists the update URL in its help pages. Then use your domain wherever
          this guide shows <code>{{ host }}</code>.
        </p>

        <h2>Step 4 — Open the door and add HTTPS</h2>
        <p>
          Picz needs an HTTPS address for your server. The easiest way is a small reverse proxy
          that gets a free certificate by itself. With <a
            href="https://caddyserver.com/docs/install"
            target="_blank"
            rel="noopener"
          >Caddy</a> on the home server, this is the whole configuration file
          (<code>Caddyfile</code>) — with your name from step 3:
        </p>
        <pre><code>{{ host }} {
    reverse_proxy localhost:9000
}</code></pre>

        <h3>4.1 Share the ports on the FRITZ!Box</h3>
        <ol>
          <li>
            Open <strong>Internet › Permit Access › Port Sharing</strong>
            (<em>Internet › Freigaben › Portfreigaben</em>).
          </li>
          <li>
            Click <strong>Add Device for Sharing</strong> (<em>Gerät für Freigaben
              hinzufügen</em>) and choose your home server.
          </li>
          <li>
            Click <strong>New Sharing</strong> (<em>Neue Freigabe</em>), choose <strong>Port
              Sharing</strong> (<em>Portfreigabe</em>) and the application <strong>HTTPS
              server</strong> (<em>HTTPS-Server</em>). This is TCP port 443. Tick
            <strong>Enable sharing via IPv4</strong> and save.
          </li>
          <li>
            Repeat for <strong>HTTP server</strong> (<em>HTTP-Server</em>), TCP port 80. Caddy
            needs port 80 to get its certificate; port 443 is where Picz connects.
          </li>
        </ol>
        <p class="help-note">
          The FRITZ!Box can use port 443 itself, for its own access from the internet. If saving
          the sharing fails for that reason, open <strong>Internet › Permit Access › FRITZ!Box
            Services</strong> (<em>Internet › Freigaben › FRITZ!Box-Dienste</em>) and give the
          box's own HTTPS access another port. Share only 80 and 443, which lead to Caddy.
        </p>

        <h3>4.2 Check it from outside</h3>
        <p>
          Turn off Wi‑Fi on your phone and open
          <code>https://{{ host }}/minio/health/live</code>. A blank page with no error means it
          works. An error or a timeout means Picz cannot reach your server either. After your
          home address changes, the name can take a few minutes to follow.
        </p>
      </template>

      <!-- Way B: the home server dials out, so DS-Lite and closed routers do not matter. -->
      <template v-else>
        <p class="help-note">
          <strong>Know the trade-off.</strong> With a tunnel, Cloudflare carries every request
          between Picz and your server and opens the HTTPS on its side, so your photos pass
          through Cloudflare on the way. They are still <em>stored</em> only in your home. If you
          want nobody in between, and your connection has its own IPv4 address, way A avoids
          this.
        </p>
        <p class="help-note">
          <strong>Videos over 100 MB do not fit through.</strong> On the free plan Cloudflare
          accepts at most 100 MB in one upload, and Picz sends every file in one piece. Photos
          are far below that; a long video is not, and cannot be stored in an album on this
          server.
        </p>

        <h2>Step 3 — Put your domain on Cloudflare and create a tunnel</h2>

        <h3>3.1 Add your domain to Cloudflare</h3>
        <ol>
          <li>
            Sign in to the <a
              href="https://dash.cloudflare.com/"
              target="_blank"
              rel="noopener"
            >Cloudflare dashboard</a> and choose <strong>Add a domain</strong>. Pick the
            <strong>Free</strong> plan.
          </li>
          <li>
            Cloudflare shows two name servers. Enter them where you bought your domain, in place
            of the old ones.
          </li>
          <li>
            Wait until Cloudflare marks the domain as <strong>Active</strong>. This takes minutes
            to a few hours, and Cloudflare sends an e-mail.
          </li>
        </ol>

        <h3>3.2 Create the tunnel</h3>
        <ol>
          <li>
            In the dashboard, open <strong>Zero Trust › Networks › Tunnels</strong> and click
            <strong>Create a tunnel</strong>.
          </li>
          <li>Choose <strong>Cloudflared</strong> as the connector and name the tunnel, for example <code>home-server</code>.</li>
          <li>
            On the next page, choose <strong>Docker</strong>. Cloudflare shows a command with
            <code>--token</code> followed by a very long string. Copy only that string: it is your
            <strong>tunnel token</strong>. Treat it like a password.
          </li>
        </ol>

        <h2>Step 4 — Connect the tunnel to MinIO</h2>

        <h3>4.1 Start the connector next to MinIO</h3>
        <p>
          Add a second service to the <code>compose.yaml</code> from step 1, paste your token, and
          run <code>docker compose up -d</code> again:
        </p>
        <pre><code>  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel --no-autoupdate run
    environment:
      TUNNEL_TOKEN: paste-your-tunnel-token-here
    restart: unless-stopped</code></pre>
        <p>
          The connector dials out to Cloudflare, so nothing on your router has to change. After a
          few seconds the dashboard shows the tunnel as <strong>Healthy</strong>.
        </p>

        <h3>4.2 Give the tunnel an address</h3>
        <ol>
          <li>
            Open your tunnel in the dashboard and go to <strong>Public Hostname</strong> (newer
            dashboards call it <strong>Published application routes</strong>). Click
            <strong>Add</strong>.
          </li>
          <li>
            Subdomain <code>photos</code>, your domain, service type <strong>HTTP</strong>, URL
            <code>minio:9000</code>. Save.
          </li>
        </ol>
        <p>
          Cloudflare creates the DNS entry and the HTTPS certificate for <code>{{ host }}</code> by
          itself. Keep it to one level below your domain — the free certificate does not cover
          a name like <code>photos.home.example.org</code>.
        </p>

        <h3>4.3 Two settings Picz needs</h3>
        <ul>
          <li>
            <strong>No caching.</strong> Open your domain, then <strong>Caching › Cache
              Rules</strong>, and create a rule: when <em>Hostname</em> equals
            <code>{{ host }}</code>, <strong>Bypass cache</strong>. Every request carries its own
            signature, and a cached answer would be the wrong one.
          </li>
          <li>
            <strong>No bot check.</strong> Picz is a program, not a browser, so it cannot solve a
            challenge. If <strong>Security › Bots › Bot Fight Mode</strong> is on, turn it off.
          </li>
        </ul>

        <h3>4.4 Check it from outside</h3>
        <p>
          Turn off Wi‑Fi on your phone and open
          <code>https://{{ host }}/minio/health/live</code>. A blank page with no error means it
          works. A Cloudflare error page means Picz cannot reach your server either — see the
          list at the end.
        </p>
      </template>

      <h2>Step 5 — Connect it to Picz</h2>
      <p>
        In Picz, open <strong>Profile → Photo storage → Add your own storage</strong>, or on the
        iPhone <strong>Options → Profile → Photo Storage</strong>. Fill in:
      </p>
      <div class="help-table-wrap">
        <table class="help-table">
          <thead>
            <tr>
              <th>Field</th>
              <th>Value</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Name</td>
              <td>Anything you like, e.g. <code>Home server</code></td>
            </tr>
            <tr>
              <td>Endpoint URL</td>
              <td><code>https://{{ host }}</code></td>
            </tr>
            <tr>
              <td>Bucket</td>
              <td><code>picz</code></td>
            </tr>
            <tr>
              <td>Region</td>
              <td><code>us-east-1</code> (MinIO's default)</td>
            </tr>
            <tr>
              <td>Access key</td>
              <td><code>picz</code></td>
            </tr>
            <tr>
              <td>Secret key</td>
              <td>The password from step 2</td>
            </tr>
            <tr>
              <td>Path-style addressing</td>
              <td>On</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p>
        Press <strong>Test connection</strong>. Picz writes a small test file to your bucket, reads
        it back and deletes it. When that works, press <strong>Save</strong>.
      </p>

      <h2>Step 6 — Create an album on it</h2>
      <p>
        Create a new album and choose your home server as its storage. Every photo you put into
        that album is now stored at home. Albums you created before stay where they are.
      </p>

      <h2>If something goes wrong</h2>
      <p>The test tells you which step failed. The usual causes:</p>
      <ul>
        <template v-if="way === 'fritzbox'">
          <li>
            <strong>It times out, or cannot connect.</strong> Picz cannot reach your server.
            Repeat the phone check from step 4.2 on mobile data. Then check the port sharing on
            the FRITZ!Box, the fixed address of the server (3.2), and that your connection has
            its own IPv4 address (3.1).
          </li>
          <li>
            <strong>A certificate error.</strong> Picz only accepts certificates that browsers
            trust. A self-signed certificate is refused — let the reverse proxy get a real one.
          </li>
          <li>
            <strong>Photos work, but large videos fail.</strong> The proxy limits the upload size.
            Caddy has no limit by default; with nginx, set <code>client_max_body_size 0;</code>.
          </li>
        </template>
        <template v-else>
          <li>
            <strong>Cloudflare error 1033, or the tunnel is not Healthy.</strong> The connector is
            not running or has the wrong token. Check <code>docker compose logs cloudflared</code>.
          </li>
          <li>
            <strong>Error 502 or "Bad gateway".</strong> The tunnel runs, but cannot reach MinIO.
            The URL in 4.2 must be <code>minio:9000</code>, and both services must be in the same
            <code>compose.yaml</code>.
          </li>
          <li>
            <strong>Error 403 with a Cloudflare page.</strong> A Cloudflare security feature
            stopped Picz. Turn off Bot Fight Mode (4.3), and look under <strong>Security ›
              Events</strong> for what else blocked the request.
          </li>
          <li>
            <strong>Photos work, but a large video fails with 413.</strong> The video is over the
            100 MB Cloudflare accepts in one upload. Keep long videos in an album on this site's
            storage.
          </li>
        </template>
        <li>
          <strong>Failed at write, "Access Denied".</strong> The policy is not attached to the user,
          or the bucket name in the policy does not match the bucket.
        </li>
        <li>
          <strong>"SignatureDoesNotMatch".</strong> The region is wrong, path-style addressing is
          off, or something on the way changes the address. <template v-if="way === 'fritzbox'">
            Caddy leaves it alone; with nginx, add <code>proxy_set_header Host $http_host;</code>.
          </template><template v-else>
            In the tunnel, do not set an <em>HTTP Host Header</em> of your own.
          </template>
        </li>
      </ul>
    </div>

    <footer class="legal-footer">
      <p>© {{ new Date().getFullYear() }} Picz</p>
      <router-link to="/">
        Home
      </router-link> |
      <router-link to="/privacy">
        Privacy
      </router-link> |
      <router-link to="/terms">
        Terms
      </router-link> |
      <router-link to="/imprint">
        Imprint
      </router-link>
    </footer>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import '@/assets/css/legal.css'

/** Way A reaches the home directly through the FRITZ!Box; way B goes through a Cloudflare Tunnel. */
type Way = 'fritzbox' | 'tunnel'

const route = useRoute()
const router = useRouter()

// In the address (`?way=tunnel`) rather than in component state, so a link can open the guide on
// the way a DS-Lite user needs, and a reload keeps the one being read.
const way = computed<Way>(() => (route.query.way === 'tunnel' ? 'tunnel' : 'fritzbox'))

/** The example address the steps use: a MyFRITZ! name for way A, a name on your own domain for B. */
const host = computed(() =>
  way.value === 'fritzbox' ? 'abc123def456.myfritz.net' : 'photos.example.org',
)

function chooseWay(next: Way) {
  // `replace`, not `push`: flipping between the two ways is reading, not navigating, and should
  // not fill the back button.
  router.replace({ query: { ...route.query, way: next } })
}
</script>

<style scoped>
/* Code blocks. The shared `.legal-content code` style is for short inline code; inside a block
   the border and padding move to the `pre`, which scrolls sideways on a phone instead of
   widening the page. */
.legal-content pre {
  margin: 0 0 var(--sp-4);
  padding: var(--sp-4);
  overflow-x: auto;
  background: var(--c-surface-alt);
  border: 1px solid var(--c-border);
  border-radius: var(--r-md);
  line-height: 1.55;
}
.legal-content pre code {
  display: block;
  padding: 0;
  border: 0;
  background: none;
  white-space: pre;
}

/* The opening statement. Deliberately the loudest thing on the page: privacy and independence
   are the reason to run a server at home at all, and the steps below only make sense after it. */
.help-manifesto {
  margin: 0 0 var(--sp-8);
  padding: var(--sp-6);
  border-left: 5px solid var(--c-accent);
  border-radius: var(--r-md);
  background: var(--c-surface);
}
.legal-content .help-manifesto-lead {
  font-family: var(--f-display);
  font-size: clamp(1.375rem, 3.5vw, 1.875rem);
  font-weight: 700;
  line-height: 1.25;
  letter-spacing: -.02em;
  color: var(--c-text);
  margin-bottom: var(--sp-4);
}
.legal-content .help-manifesto p:not(.help-manifesto-lead) {
  font-size: 1.0625rem;
  color: var(--c-text);
}
.legal-content .help-manifesto p:last-child {
  margin-bottom: 0;
}

/* The two ways in. Side by side where there is room, stacked on a phone. */
.help-ways {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: var(--sp-3);
  margin-bottom: var(--sp-6);
}
.help-way {
  display: flex;
  flex-direction: column;
  gap: var(--sp-1, 4px);
  padding: var(--sp-4);
  text-align: left;
  font: inherit;
  color: var(--c-text-2);
  background: var(--c-surface);
  border: 1.5px solid var(--c-border);
  border-radius: var(--r-md);
  cursor: pointer;
}
.help-way:hover {
  border-color: var(--c-accent);
}
.help-way.is-active {
  border-color: var(--c-accent);
  box-shadow: inset 0 0 0 1.5px var(--c-accent);
}
.help-way-tag {
  font-size: .75rem;
  font-weight: 600;
  letter-spacing: .04em;
  text-transform: uppercase;
  color: var(--c-accent);
}
.help-way-title {
  font-weight: 600;
  font-size: 1.0625rem;
  color: var(--c-text);
}
.help-way-text {
  font-size: .875rem;
  line-height: 1.55;
}

.legal-content .help-way-reminder {
  margin-top: var(--sp-8);
  font-size: .875rem;
  color: var(--c-text-3);
}
/* A button, because it changes the page rather than going somewhere; drawn as a link. */
.help-way-switch {
  padding: 0;
  font: inherit;
  color: var(--c-accent);
  background: none;
  border: 0;
  cursor: pointer;
  text-decoration: underline;
}

.legal-content .help-menu-hint {
  font-size: .875rem;
  color: var(--c-text-3);
}

/* Things that stop people cold if they miss them, set apart from the running text. */
.legal-content .help-note {
  padding: var(--sp-3) var(--sp-4);
  border-left: 3px solid var(--c-accent);
  border-radius: var(--r-md);
  background: var(--c-surface);
  font-size: .875rem;
}

.help-table-wrap {
  overflow-x: auto;
  margin-bottom: var(--sp-4);
}
.help-table {
  width: 100%;
  border-collapse: collapse;
  font-size: .9375rem;
}
.help-table th,
.help-table td {
  padding: var(--sp-2) var(--sp-3);
  border-bottom: 1px solid var(--c-border);
  text-align: left;
  color: var(--c-text-2);
  vertical-align: top;
}
.help-table th {
  color: var(--c-text);
  font-weight: 600;
}
</style>
