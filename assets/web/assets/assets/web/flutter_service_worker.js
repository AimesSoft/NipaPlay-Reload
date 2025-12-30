'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "a26ee5f7823a26b8e6d51ef8d3f1c980",
"version.json": "eee8e3338016d7057083b80ca7361bae",
"index.html": "78ad6e83e3b6bafeec9aefb29bf8bcb3",
"/": "78ad6e83e3b6bafeec9aefb29bf8bcb3",
"main.dart.js": "29f49bcdd048ecd345c40347eeaba2ec",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"favicon.png": "47b20364be4db6e6c4dc8916a9ab5630",
"icons/Icon-192.png": "6b4e52feb3fc0f6ef5814e29e6a18380",
"icons/Icon-maskable-192.png": "6b4e52feb3fc0f6ef5814e29e6a18380",
"icons/Icon-maskable-512.png": "0754a735be0769e88eb208c47a8fa10d",
"icons/Icon-512.png": "0754a735be0769e88eb208c47a8fa10d",
"manifest.json": "82a33b002b079392689a0800c3408420",
"assets/others/%25E8%25B5%259E%25E8%25B5%258F%25E7%25A0%2581.jpg": "1cb4cd9419a34ff88cb4fb64658ba5c6",
"assets/NOTICES": "af39df6e40c334f72886896d17375c6a",
"assets/FontManifest.json": "4d244c7e9710838224c019aa7ed0ae7e",
"assets/AssetManifest.bin.json": "6f02559fc3f78b9428652ef98fb9b7cf",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "e624ee9688cd575fa51a94de45008f7d",
"assets/packages/media_kit/assets/web/hls1.4.10.js": "bd60e2701c42b6bf2c339dcf5d495865",
"assets/packages/kmbal_ionicons/assets/fonts/Ionicons.ttf": "fa2ce876437098e58dbb33f13fc1c4c6",
"assets/packages/hugeicons/lib/fonts/hugeicons-stroke-rounded.ttf": "ed1746fbad500fea94f6e5c5eb97ed7d",
"assets/packages/fluent_ui/fonts/FluentIcons.ttf": "f3c4f09a37ace3246250ff7142da5cdd",
"assets/packages/fluent_ui/assets/AcrylicNoise.png": "81f27726c45346351eca125bd062e9a7",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/AssetManifest.bin": "3744d42afaca17c1c76081c75296a815",
"assets/fonts/MaterialIcons-Regular.otf": "b1b051caed0501e7a7ba9f5cf3f6788a",
"assets/assets/jellyfin.svg": "2f22653e4930732b5bbc0ea2f5258c59",
"assets/assets/images/main_image2.png": "18bfb65d272f290a1e2f0e3d926cd642",
"assets/assets/images/logo512.png": "7661166f68a8f82b1c5c8bd40b2ebfe5",
"assets/assets/images/main_image_mobile2.png": "86c5a4992720f47f583a591a3fc718a8",
"assets/assets/images/main_image_mobile.png": "51f9f53704488d594240f71bcf1d3316",
"assets/assets/images/main_image.png": "7babdd16fdf67bac496b857a1cef1029",
"assets/assets/nipaplay.png": "103ebbeb9db841efa31d79b1b174b59d",
"assets/assets/web/flutter_bootstrap.js": "c852e1038e11c638f3f408d183ab4b4a",
"assets/assets/web/version.json": "eee8e3338016d7057083b80ca7361bae",
"assets/assets/web/index.html": "78ad6e83e3b6bafeec9aefb29bf8bcb3",
"assets/assets/web/main.dart.js": "449e7077fdf5024af93435843b304397",
"assets/assets/web/flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"assets/assets/web/favicon.png": "47b20364be4db6e6c4dc8916a9ab5630",
"assets/assets/web/icons/Icon-192.png": "6b4e52feb3fc0f6ef5814e29e6a18380",
"assets/assets/web/icons/Icon-maskable-192.png": "6b4e52feb3fc0f6ef5814e29e6a18380",
"assets/assets/web/icons/Icon-maskable-512.png": "0754a735be0769e88eb208c47a8fa10d",
"assets/assets/web/icons/Icon-512.png": "0754a735be0769e88eb208c47a8fa10d",
"assets/assets/web/manifest.json": "82a33b002b079392689a0800c3408420",
"assets/assets/web/assets/NOTICES": "af39df6e40c334f72886896d17375c6a",
"assets/assets/web/assets/FontManifest.json": "4d244c7e9710838224c019aa7ed0ae7e",
"assets/assets/web/assets/AssetManifest.bin.json": "6f02559fc3f78b9428652ef98fb9b7cf",
"assets/assets/web/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "e624ee9688cd575fa51a94de45008f7d",
"assets/assets/web/assets/packages/media_kit/assets/web/hls1.4.10.js": "bd60e2701c42b6bf2c339dcf5d495865",
"assets/assets/web/assets/packages/kmbal_ionicons/assets/fonts/Ionicons.ttf": "fa2ce876437098e58dbb33f13fc1c4c6",
"assets/assets/web/assets/packages/hugeicons/lib/fonts/hugeicons-stroke-rounded.ttf": "ed1746fbad500fea94f6e5c5eb97ed7d",
"assets/assets/web/assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/assets/web/assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/assets/web/assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/assets/web/assets/AssetManifest.bin": "3744d42afaca17c1c76081c75296a815",
"assets/assets/web/assets/fonts/MaterialIcons-Regular.otf": "022162257afe6602448a961c2c8c4263",
"assets/assets/web/assets/assets/jellyfin.svg": "2f22653e4930732b5bbc0ea2f5258c59",
"assets/assets/web/assets/assets/images/main_image2.png": "18bfb65d272f290a1e2f0e3d926cd642",
"assets/assets/web/assets/assets/images/logo512.png": "7661166f68a8f82b1c5c8bd40b2ebfe5",
"assets/assets/web/assets/assets/images/main_image_mobile2.png": "86c5a4992720f47f583a591a3fc718a8",
"assets/assets/web/assets/assets/images/main_image_mobile.png": "51f9f53704488d594240f71bcf1d3316",
"assets/assets/web/assets/assets/images/main_image.png": "7babdd16fdf67bac496b857a1cef1029",
"assets/assets/web/assets/assets/nipaplay.png": "103ebbeb9db841efa31d79b1b174b59d",
"assets/assets/web/assets/assets/dandanplay.png": "6d0fd3c047b14db644dac16f8f620e07",
"assets/assets/web/assets/assets/bangumi.png": "6518e3b975cc05594ea129fd9dc14eee",
"assets/assets/web/assets/assets/logo.png": "f880406c7149bd2f4c01bfe777557067",
"assets/assets/web/assets/assets/emby.svg": "0d928debc4b17cc6fd6f3e61351f3c9c",
"assets/assets/web/assets/assets/subfont.ttf": "9ffae59e10271561ebf0a4199b252891",
"assets/assets/web/assets/assets/backempty.png": "747801ce3d264a577243883a95f737ff",
"assets/assets/web/canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"assets/assets/web/canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"assets/assets/web/canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"assets/assets/web/canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"assets/assets/web/canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"assets/assets/web/canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"assets/assets/web/canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"assets/assets/web/canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"assets/assets/web/canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"assets/assets/web/canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"assets/assets/web/canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"assets/assets/web/canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"assets/assets/dandanplay.png": "6d0fd3c047b14db644dac16f8f620e07",
"assets/assets/bangumi.png": "6518e3b975cc05594ea129fd9dc14eee",
"assets/assets/logo.png": "f880406c7149bd2f4c01bfe777557067",
"assets/assets/emby.svg": "0d928debc4b17cc6fd6f3e61351f3c9c",
"assets/assets/shaders/anime4k/Anime4K_Restore_CNN_Soft_M.glsl": "e5618d9eeb8830e690d843daa1c1a610",
"assets/assets/shaders/anime4k/Anime4K_Upscale_Denoise_CNN_x2_M.glsl": "6ec56c1d3650a1adc8884b6520e2b43a",
"assets/assets/shaders/anime4k/Anime4K_Clamp_Highlights.glsl": "91bf7fb4b4b64e6184b59211d26dd4d1",
"assets/assets/subfont.ttf": "9ffae59e10271561ebf0a4199b252891",
"assets/assets/backempty.png": "747801ce3d264a577243883a95f737ff",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
