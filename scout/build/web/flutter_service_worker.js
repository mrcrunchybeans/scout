'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"android-chrome-192x192.png": "d866ec1b789aeeb8b39364fe8f731bb0",
"android-chrome-512x512.png": "df612c7ce07e4ca5efdc3054124c13a3",
"apple-touch-icon.png": "9805c4429a2008c9e88b71bac98d7f24",
"assets/AssetManifest.bin": "b11f8f02b14e3437ef0b131c51b90318",
"assets/AssetManifest.bin.json": "18413527afc1e6a92ea98f4dfee689f9",
"assets/AssetManifest.json": "cbbb8f25d7a6efcab54429e02d4a1ecf",
"assets/assets/fonts/Inter-Bold.ttf": "a041f18d0d0c67b376bec0343f7c0cf0",
"assets/assets/fonts/Inter-Regular.ttf": "0a77e23a8fdbe6caefd53cb04c26fabc",
"assets/assets/images/scout%2520dash%2520logo%2520dark%2520mode.png": "5d632f985b762c5e3a1210669d180a3f",
"assets/assets/images/scout%2520dash%2520logo%2520dark%2520mode@2x.png": "57fc48300720ad59e3e0dc3e8824a2d9",
"assets/assets/images/scout%2520dash%2520logo%2520dark%2520mode@3x.png": "160c9ad255627870fd2f4d0149abd5d4",
"assets/assets/images/scout%2520dash%2520logo%2520dark%2520mode_full.png": "dddb237bf28046cca6a5feca09d631e7",
"assets/assets/images/scout%2520dash%2520logo%2520light%2520mode.png": "2381ede0ea4be8c9f0e3c2cccb023a00",
"assets/assets/images/scout%2520dash%2520logo%2520light%2520mode@2x.png": "43090bc1e4ab8515e7475771e592054a",
"assets/assets/images/scout%2520dash%2520logo%2520light%2520mode@3x.png": "e091673e886090e7fc52b3a5aeec5f02",
"assets/assets/images/scout%2520dash%2520logo%2520light%2520mode_full.png": "8dd7e97b7eb76fac9c790e6ba8c6fc57",
"assets/assets/images/scout_logo.png": "dd660d5200ae0ad0815cc3978eaa6a1f",
"assets/assets/images/scout_logo.webp": "155bd1f559b971889f9739778bcdd7f4",
"assets/FontManifest.json": "5071136d75de91fbed73e57967983511",
"assets/fonts/MaterialIcons-Regular.otf": "e0988ce8730c6386960eafd5eb9680f4",
"assets/images/scout_logo.png": "dd660d5200ae0ad0815cc3978eaa6a1f",
"assets/images/scout_logo.webp": "155bd1f559b971889f9739778bcdd7f4",
"assets/NOTICES": "3a43e00267456426035c0b1fe774606d",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"budget-sw.js": "32852ffaf84f7d361d463bb5c1cdc66c",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"favicon-16x16.png": "453256946de7ec34135df66cd4eb1127",
"favicon-32x32.png": "276920e2d0229d89e5621dffc386ee44",
"favicon-96x96.png": "148a66efff9ad053e68c340a13aeb12b",
"favicon.ico": "6b8c9d7cd938adb1ebc413470d42e2ee",
"favicon.png": "f4114db26aa8941a23a9563c3f3a55f8",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"flutter_bootstrap.js": "e0dcf2ced76d8c8ea752082e32c70688",
"functions/budget/%5B%5Bpath%5D%5D.js": "cab8e533bdf41fd2e21410e8d359e713",
"icons/apple-touch-icon.png": "9805c4429a2008c9e88b71bac98d7f24",
"icons/favicon-96x96.png": "148a66efff9ad053e68c340a13aeb12b",
"icons/favicon.ico": "6b8c9d7cd938adb1ebc413470d42e2ee",
"icons/Icon-192.png": "d41d8cd98f00b204e9800998ecf8427e",
"icons/Icon-512.png": "d41d8cd98f00b204e9800998ecf8427e",
"icons/Icon-maskable-192.png": "d41d8cd98f00b204e9800998ecf8427e",
"icons/Icon-maskable-512.png": "d41d8cd98f00b204e9800998ecf8427e",
"icons/site.webmanifest": "fbb12cd15da6a32244a3dcea85b486b8",
"icons/web-app-manifest-192x192.png": "bd3d7daede3a1d5b43ed160db2ee5a1c",
"icons/web-app-manifest-512x512.png": "32c74afaefbc5c775a4eb698149550fb",
"index.html": "c5562309dbd36b915f4debf42a25620d",
"/": "c5562309dbd36b915f4debf42a25620d",
"main.dart.js": "233ae99ed05792df107b5c126c53bbe2",
"manifest.json": "6e32f1bf590284f7a732bcaffd7d23fd",
"site.webmanifest": "88e34eda67b59738b61ae287d521a194",
"splash/img/dark-1x.png": "4c2c5747395b43ef2b0b9ff4dd8f2af6",
"splash/img/dark-2x.png": "f6aad75de5542f7859b8ac6a4e980ed5",
"splash/img/dark-3x.png": "121ed28098fc02579d91b05a5ddafa1f",
"splash/img/dark-4x.png": "8c2d4c21797602556955bfdc9a5c95f6",
"splash/img/light-1x.png": "75c2dfde9a24c17af7e8dde4b07d19ba",
"splash/img/light-2x.png": "40183d194b538ccbc23d3a175edb9b22",
"splash/img/light-3x.png": "6e6188fdfea25c5e560b915eaf9ac40a",
"splash/img/light-4x.png": "bc9179e2f64421e91795ca74dde9ac74",
"version.json": "393d5d7c0aefd3fd64ff80fa6cecaad8",
"web-app-manifest-192x192.png": "bd3d7daede3a1d5b43ed160db2ee5a1c",
"web-app-manifest-512x512.png": "32c74afaefbc5c775a4eb698149550fb"};
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
