'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "712070e95fb099a5908b3bbf567fca13",
"version.json": "391b397f0eb3c6d691f78a2ea2f7acbf",
"index.html": "78ad6e83e3b6bafeec9aefb29bf8bcb3",
"/": "78ad6e83e3b6bafeec9aefb29bf8bcb3",
"main.dart.js": "f462e76a126ec002cd11cdcb1fb07877",
"flutter.js": "76f08d47ff9f5715220992f993002504",
"favicon.png": "275cc3b38c1350190db92bc3bac5558e",
"icons/Icon-192.png": "6e865d65533003b6c905e22b72ccac77",
"icons/Icon-maskable-192.png": "6e865d65533003b6c905e22b72ccac77",
"icons/Icon-maskable-512.png": "777621e540096477503ad4a8b3c1b9ed",
"icons/Icon-512.png": "777621e540096477503ad4a8b3c1b9ed",
"manifest.json": "845370ef33e107a1d7961f599c05b97d",
"assets/AssetManifest.json": "2b60b8aa44c7f3d4c4de746a6a143ae9",
"assets/NOTICES": "5a7c5f9bf93313635556c4b22355bd1f",
"assets/FontManifest.json": "58318b9f7d8707d36b1cba2066589b25",
"assets/AssetManifest.bin.json": "0ff39cb2b60dbc0bab8cad3486040e68",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/media_kit/assets/web/hls1.4.10.js": "bd60e2701c42b6bf2c339dcf5d495865",
"assets/packages/kmbal_ionicons/assets/fonts/Ionicons.ttf": "fa2ce876437098e58dbb33f13fc1c4c6",
"assets/packages/hugeicons/lib/fonts/hugeicons-stroke-rounded.ttf": "ed1746fbad500fea94f6e5c5eb97ed7d",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "a44144ea02e4a6723e6972dcf1f2e0dc",
"assets/fonts/MaterialIcons-Regular.otf": "c5c301825f780ef53905001b97198764",
"assets/assets/jellyfin.svg": "2f22653e4930732b5bbc0ea2f5258c59",
"assets/assets/unmaxbuttonLight.png": "3588fd4155681b6bc96ca8518265c2cc",
"assets/assets/maxbuttonLight.png": "342855132e6b0e86160d1e098995d92b",
"assets/assets/images/logo512.png": "3799d79d9158b7a28ac2cadb634a3017",
"assets/assets/images/main_image_mobile.png": "51f9f53704488d594240f71bcf1d3316",
"assets/assets/images/anime1.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/images/recent1.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/images/anime2.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/images/recent2.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/images/main_image.png": "7babdd16fdf67bac496b857a1cef1029",
"assets/assets/web/flutter_bootstrap.js": "c7b5de6dc6243391aee4c8d556b743cc",
"assets/assets/web/version.json": "391b397f0eb3c6d691f78a2ea2f7acbf",
"assets/assets/web/index.html": "78ad6e83e3b6bafeec9aefb29bf8bcb3",
"assets/assets/web/main.dart.js": "a195b25a6760752242b90e730d9d6b71",
"assets/assets/web/flutter.js": "76f08d47ff9f5715220992f993002504",
"assets/assets/web/favicon.png": "275cc3b38c1350190db92bc3bac5558e",
"assets/assets/web/icons/Icon-192.png": "6e865d65533003b6c905e22b72ccac77",
"assets/assets/web/icons/Icon-maskable-192.png": "6e865d65533003b6c905e22b72ccac77",
"assets/assets/web/icons/Icon-maskable-512.png": "777621e540096477503ad4a8b3c1b9ed",
"assets/assets/web/icons/Icon-512.png": "777621e540096477503ad4a8b3c1b9ed",
"assets/assets/web/manifest.json": "845370ef33e107a1d7961f599c05b97d",
"assets/assets/web/assets/AssetManifest.json": "2b60b8aa44c7f3d4c4de746a6a143ae9",
"assets/assets/web/assets/NOTICES": "5a7c5f9bf93313635556c4b22355bd1f",
"assets/assets/web/assets/FontManifest.json": "58318b9f7d8707d36b1cba2066589b25",
"assets/assets/web/assets/AssetManifest.bin.json": "0ff39cb2b60dbc0bab8cad3486040e68",
"assets/assets/web/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/assets/web/assets/packages/media_kit/assets/web/hls1.4.10.js": "bd60e2701c42b6bf2c339dcf5d495865",
"assets/assets/web/assets/packages/kmbal_ionicons/assets/fonts/Ionicons.ttf": "fa2ce876437098e58dbb33f13fc1c4c6",
"assets/assets/web/assets/packages/hugeicons/lib/fonts/hugeicons-stroke-rounded.ttf": "ed1746fbad500fea94f6e5c5eb97ed7d",
"assets/assets/web/assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/assets/web/assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/assets/web/assets/AssetManifest.bin": "a44144ea02e4a6723e6972dcf1f2e0dc",
"assets/assets/web/assets/fonts/MaterialIcons-Regular.otf": "c5c301825f780ef53905001b97198764",
"assets/assets/web/assets/assets/jellyfin.svg": "2f22653e4930732b5bbc0ea2f5258c59",
"assets/assets/web/assets/assets/unmaxbuttonLight.png": "3588fd4155681b6bc96ca8518265c2cc",
"assets/assets/web/assets/assets/maxbuttonLight.png": "342855132e6b0e86160d1e098995d92b",
"assets/assets/web/assets/assets/images/logo512.png": "3799d79d9158b7a28ac2cadb634a3017",
"assets/assets/web/assets/assets/images/main_image_mobile.png": "51f9f53704488d594240f71bcf1d3316",
"assets/assets/web/assets/assets/images/anime1.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/web/assets/assets/images/recent1.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/web/assets/assets/images/anime2.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/web/assets/assets/images/recent2.png": "d59b82421dadadb0760316bfd7afc702",
"assets/assets/web/assets/assets/images/main_image.png": "7babdd16fdf67bac496b857a1cef1029",
"assets/assets/web/assets/assets/maxbutton.png": "c5f16fb5dcc294bb399e1d3098cb6218",
"assets/assets/web/assets/assets/backgirl.png": "f28302e3586a7616cc03ab0fc2ebe7f3",
"assets/assets/web/assets/assets/minbuttonLight.png": "23de48e5ff33882d51b5568f14b80351",
"assets/assets/web/assets/assets/logo.png": "f880406c7149bd2f4c01bfe777557067",
"assets/assets/web/assets/assets/emby.svg": "0d928debc4b17cc6fd6f3e61351f3c9c",
"assets/assets/web/assets/assets/unmaxbutton.png": "931e769ef675c5d0d4ae434a7dcb4242",
"assets/assets/web/assets/assets/minbutton.png": "7d4dd7bc027c3baff640560727fda187",
"assets/assets/web/assets/assets/closebuttonLight.png": "13ab647b41220dd69790b6fcdcd25581",
"assets/assets/web/assets/assets/subfont.ttf": "9ffae59e10271561ebf0a4199b252891",
"assets/assets/web/assets/assets/closebutton.png": "1f14d6b766c9d29fc24a738b0e3daf82",
"assets/assets/web/assets/assets/backempty.png": "747801ce3d264a577243883a95f737ff",
"assets/assets/web/canvaskit/skwasm_st.js": "d1326ceef381ad382ab492ba5d96f04d",
"assets/assets/web/canvaskit/skwasm.js": "f2ad9363618c5f62e813740099a80e63",
"assets/assets/web/canvaskit/skwasm.js.symbols": "80806576fa1056b43dd6d0b445b4b6f7",
"assets/assets/web/canvaskit/canvaskit.js.symbols": "68eb703b9a609baef8ee0e413b442f33",
"assets/assets/web/canvaskit/skwasm.wasm": "f0dfd99007f989368db17c9abeed5a49",
"assets/assets/web/canvaskit/chromium/canvaskit.js.symbols": "5a23598a2a8efd18ec3b60de5d28af8f",
"assets/assets/web/canvaskit/chromium/canvaskit.js": "34beda9f39eb7d992d46125ca868dc61",
"assets/assets/web/canvaskit/chromium/canvaskit.wasm": "64a386c87532ae52ae041d18a32a3635",
"assets/assets/web/canvaskit/skwasm_st.js.symbols": "c7e7aac7cd8b612defd62b43e3050bdd",
"assets/assets/web/canvaskit/canvaskit.js": "86e461cf471c1640fd2b461ece4589df",
"assets/assets/web/canvaskit/canvaskit.wasm": "efeeba7dcc952dae57870d4df3111fad",
"assets/assets/web/canvaskit/skwasm_st.wasm": "56c3973560dfcbf28ce47cebe40f3206",
"assets/assets/maxbutton.png": "c5f16fb5dcc294bb399e1d3098cb6218",
"assets/assets/backgirl.png": "f28302e3586a7616cc03ab0fc2ebe7f3",
"assets/assets/minbuttonLight.png": "23de48e5ff33882d51b5568f14b80351",
"assets/assets/logo.png": "f880406c7149bd2f4c01bfe777557067",
"assets/assets/emby.svg": "0d928debc4b17cc6fd6f3e61351f3c9c",
"assets/assets/unmaxbutton.png": "931e769ef675c5d0d4ae434a7dcb4242",
"assets/assets/minbutton.png": "7d4dd7bc027c3baff640560727fda187",
"assets/assets/closebuttonLight.png": "13ab647b41220dd69790b6fcdcd25581",
"assets/assets/subfont.ttf": "9ffae59e10271561ebf0a4199b252891",
"assets/assets/closebutton.png": "1f14d6b766c9d29fc24a738b0e3daf82",
"assets/assets/backempty.png": "747801ce3d264a577243883a95f737ff",
"canvaskit/skwasm_st.js": "d1326ceef381ad382ab492ba5d96f04d",
"canvaskit/skwasm.js": "f2ad9363618c5f62e813740099a80e63",
"canvaskit/skwasm.js.symbols": "80806576fa1056b43dd6d0b445b4b6f7",
"canvaskit/canvaskit.js.symbols": "68eb703b9a609baef8ee0e413b442f33",
"canvaskit/skwasm.wasm": "f0dfd99007f989368db17c9abeed5a49",
"canvaskit/chromium/canvaskit.js.symbols": "5a23598a2a8efd18ec3b60de5d28af8f",
"canvaskit/chromium/canvaskit.js": "34beda9f39eb7d992d46125ca868dc61",
"canvaskit/chromium/canvaskit.wasm": "64a386c87532ae52ae041d18a32a3635",
"canvaskit/skwasm_st.js.symbols": "c7e7aac7cd8b612defd62b43e3050bdd",
"canvaskit/canvaskit.js": "86e461cf471c1640fd2b461ece4589df",
"canvaskit/canvaskit.wasm": "efeeba7dcc952dae57870d4df3111fad",
"canvaskit/skwasm_st.wasm": "56c3973560dfcbf28ce47cebe40f3206"};
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
