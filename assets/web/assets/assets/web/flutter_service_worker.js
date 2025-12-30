'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "0b8834074aefb0d4c1c78079ca8fa9db",
"version.json": "7b8629f3da85986ab1e78cef9744c65f",
"index.html": "78ad6e83e3b6bafeec9aefb29bf8bcb3",
"/": "78ad6e83e3b6bafeec9aefb29bf8bcb3",
"main.dart.js": "0e0d43a658b6668729d830dcc96f324d",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"favicon.png": "275cc3b38c1350190db92bc3bac5558e",
"icons/Icon-192.png": "6e865d65533003b6c905e22b72ccac77",
"icons/Icon-maskable-192.png": "6e865d65533003b6c905e22b72ccac77",
"icons/Icon-maskable-512.png": "777621e540096477503ad4a8b3c1b9ed",
"icons/Icon-512.png": "777621e540096477503ad4a8b3c1b9ed",
"manifest.json": "845370ef33e107a1d7961f599c05b97d",
"assets/AssetManifest.json": "348b4cd9024717b00eb7270b9fab0453",
"assets/NOTICES": "9260960245d1c4d45ab6b0acc00fc438",
"assets/FontManifest.json": "4d244c7e9710838224c019aa7ed0ae7e",
"assets/AssetManifest.bin.json": "ac117eac0ab58d379b356357c94d8874",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/media_kit/assets/web/hls1.4.10.js": "bd60e2701c42b6bf2c339dcf5d495865",
"assets/packages/kmbal_ionicons/assets/fonts/Ionicons.ttf": "fa2ce876437098e58dbb33f13fc1c4c6",
"assets/packages/hugeicons/lib/fonts/hugeicons-stroke-rounded.ttf": "ed1746fbad500fea94f6e5c5eb97ed7d",
"assets/packages/fluent_ui/fonts/FluentIcons.ttf": "f3c4f09a37ace3246250ff7142da5cdd",
"assets/packages/fluent_ui/assets/AcrylicNoise.png": "81f27726c45346351eca125bd062e9a7",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "4954980a3de6c747fd1b3545a0235f11",
"assets/fonts/MaterialIcons-Regular.otf": "fee8c151d73825d332af989bbc50d319",
"assets/assets/jellyfin.svg": "2f22653e4930732b5bbc0ea2f5258c59",
"assets/assets/images/logo512.png": "3799d79d9158b7a28ac2cadb634a3017",
"assets/assets/images/main_image_mobile.png": "51f9f53704488d594240f71bcf1d3316",
"assets/assets/images/anime1.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/images/recent1.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/images/anime2.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/images/recent2.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/images/main_image.png": "7babdd16fdf67bac496b857a1cef1029",
"assets/assets/web/flutter_bootstrap.js": "e2bc01e1c24cacd6ea57f6028424518a",
"assets/assets/web/version.json": "7b8629f3da85986ab1e78cef9744c65f",
"assets/assets/web/index.html": "78ad6e83e3b6bafeec9aefb29bf8bcb3",
"assets/assets/web/main.dart.js": "203f34201d3625e860705a65f6f38297",
"assets/assets/web/flutter.js": "888483df48293866f9f41d3d9274a779",
"assets/assets/web/favicon.png": "275cc3b38c1350190db92bc3bac5558e",
"assets/assets/web/icons/Icon-192.png": "6e865d65533003b6c905e22b72ccac77",
"assets/assets/web/icons/Icon-maskable-192.png": "6e865d65533003b6c905e22b72ccac77",
"assets/assets/web/icons/Icon-maskable-512.png": "777621e540096477503ad4a8b3c1b9ed",
"assets/assets/web/icons/Icon-512.png": "777621e540096477503ad4a8b3c1b9ed",
"assets/assets/web/manifest.json": "845370ef33e107a1d7961f599c05b97d",
"assets/assets/web/assets/AssetManifest.json": "348b4cd9024717b00eb7270b9fab0453",
"assets/assets/web/assets/NOTICES": "9260960245d1c4d45ab6b0acc00fc438",
"assets/assets/web/assets/FontManifest.json": "4d244c7e9710838224c019aa7ed0ae7e",
"assets/assets/web/assets/AssetManifest.bin.json": "ac117eac0ab58d379b356357c94d8874",
"assets/assets/web/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/assets/web/assets/packages/media_kit/assets/web/hls1.4.10.js": "bd60e2701c42b6bf2c339dcf5d495865",
"assets/assets/web/assets/packages/kmbal_ionicons/assets/fonts/Ionicons.ttf": "fa2ce876437098e58dbb33f13fc1c4c6",
"assets/assets/web/assets/packages/hugeicons/lib/fonts/hugeicons-stroke-rounded.ttf": "ed1746fbad500fea94f6e5c5eb97ed7d",
"assets/assets/web/assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/assets/web/assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/assets/web/assets/AssetManifest.bin": "4954980a3de6c747fd1b3545a0235f11",
"assets/assets/web/assets/fonts/MaterialIcons-Regular.otf": "fee8c151d73825d332af989bbc50d319",
"assets/assets/web/assets/assets/jellyfin.svg": "2f22653e4930732b5bbc0ea2f5258c59",
"assets/assets/web/assets/assets/images/logo512.png": "3799d79d9158b7a28ac2cadb634a3017",
"assets/assets/web/assets/assets/images/main_image_mobile.png": "51f9f53704488d594240f71bcf1d3316",
"assets/assets/web/assets/assets/images/anime1.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/web/assets/assets/images/recent1.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/web/assets/assets/images/anime2.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/web/assets/assets/images/recent2.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/web/assets/assets/images/main_image.png": "7babdd16fdf67bac496b857a1cef1029",
"assets/assets/web/assets/assets/backgirl.png": "f28302e3586a7616cc03ab0fc2ebe7f3",
"assets/assets/web/assets/assets/logo.png": "f880406c7149bd2f4c01bfe777557067",
"assets/assets/web/assets/assets/emby.svg": "0d928debc4b17cc6fd6f3e61351f3c9c",
"assets/assets/web/assets/assets/subfont.ttf": "9ffae59e10271561ebf0a4199b252891",
"assets/assets/web/assets/assets/backempty.png": "747801ce3d264a577243883a95f737ff",
"assets/assets/web/canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"assets/assets/web/canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"assets/assets/web/canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"assets/assets/web/canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"assets/assets/web/canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"assets/assets/web/canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"assets/assets/web/canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"assets/assets/web/canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"assets/assets/web/canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"assets/assets/web/canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"assets/assets/web/canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"assets/assets/web/canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"assets/assets/backgirl.png": "f28302e3586a7616cc03ab0fc2ebe7f3",
"assets/assets/logo.png": "f880406c7149bd2f4c01bfe777557067",
"assets/assets/emby.svg": "0d928debc4b17cc6fd6f3e61351f3c9c",
"assets/assets/subfont.ttf": "9ffae59e10271561ebf0a4199b252891",
"assets/assets/backempty.png": "747801ce3d264a577243883a95f737ff",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b"};
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
