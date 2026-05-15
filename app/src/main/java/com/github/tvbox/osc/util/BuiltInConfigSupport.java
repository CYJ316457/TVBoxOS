package com.github.tvbox.osc.util;

import android.text.TextUtils;

public final class BuiltInConfigSupport {

    public static final String DEFAULT_CONFIG_URL = "asset://builtin/demo_config.json";
    private static final String ASSET_SCHEME = "asset://";
    private static final String ASSETS_SCHEME = "assets://";

    private BuiltInConfigSupport() {
    }

    public static boolean isAssetUrl(String url) {
        return !TextUtils.isEmpty(url) && (url.startsWith(ASSET_SCHEME) || url.startsWith(ASSETS_SCHEME));
    }

    public static String readConfig(String url) {
        return readAssetUrl(url);
    }

    public static String readSiteHome(String apiUrl) {
        return readSiteAsset(apiUrl, "home.json");
    }

    public static String readSiteCategory(String apiUrl, String categoryId) {
        return readSiteAsset(apiUrl, "category_" + safeFileName(categoryId) + ".json", "category_default.json", "home.json");
    }

    public static String readSiteDetail(String apiUrl, String detailId) {
        return readSiteAsset(apiUrl, "detail_" + safeFileName(detailId) + ".json", "detail_default.json");
    }

    public static String readSiteSearch(String apiUrl) {
        return readSiteAsset(apiUrl, "search.json", "category_featured.json", "home.json");
    }

    private static String readSiteAsset(String apiUrl, String... candidates) {
        if (!isAssetUrl(apiUrl)) return "";
        String base = stripScheme(apiUrl);
        if (base.endsWith(".json")) {
            base = base.substring(0, base.length() - 5);
        }
        if (base.endsWith("/")) {
            base = base.substring(0, base.length() - 1);
        }
        for (String candidate : candidates) {
            String content = FileUtils.getAsOpen(base + "/" + candidate);
            if (!TextUtils.isEmpty(content)) return content;
        }
        return "";
    }

    private static String readAssetUrl(String url) {
        if (!isAssetUrl(url)) return "";
        return FileUtils.getAsOpen(stripScheme(url));
    }

    private static String stripScheme(String url) {
        if (url.startsWith(ASSETS_SCHEME)) {
            return url.substring(ASSETS_SCHEME.length());
        }
        return url.substring(ASSET_SCHEME.length());
    }

    private static String safeFileName(String value) {
        if (TextUtils.isEmpty(value)) return "default";
        return value.replaceAll("[^a-zA-Z0-9._-]", "_");
    }
}
