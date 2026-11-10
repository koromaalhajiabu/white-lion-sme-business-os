package com.whitelion.sme;

import android.app.Activity;
import android.os.Bundle;
import android.content.Intent;
import android.net.Uri;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.ValueCallback;
import android.webkit.ConsoleMessage;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Button;
import android.graphics.Color;

import androidx.webkit.WebViewAssetLoader;

public class MainActivity extends Activity {
    private static final String ASSET_HOST = "appassets.androidplatform.net";
    private static final String APP_ASSET_URL =
            "https://appassets.androidplatform.net/assets/site/index.html";
    private static final String APP_URL =
            "https://koromaalhajiabu.github.io/white-lion-sme-business-os/";
    private static final int FILE_PICKER_REQUEST = 4102;

    private WebView webView;
    private WebViewAssetLoader assetLoader;
    private ValueCallback<Uri[]> filePathCallback;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(16, 26, 45));
        getWindow().setNavigationBarColor(Color.rgb(16, 26, 45));
        openApplication(savedInstanceState);
    }

    private void openApplication(Bundle state) {
        assetLoader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();

        webView = new WebView(this);
        webView.setBackgroundColor(Color.WHITE);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadsImagesAutomatically(true);
        settings.setJavaScriptCanOpenWindowsAutomatically(true);
        settings.setSupportMultipleWindows(false);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setMediaPlaybackRequiresUserGesture(false);

        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(webView, true);

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                    FileChooserParams params) {
                if (filePathCallback != null) filePathCallback.onReceiveValue(null);
                filePathCallback = callback;
                Intent intent = params.createIntent();
                try {
                    startActivityForResult(intent, FILE_PICKER_REQUEST);
                    return true;
                } catch (Exception e) {
                    filePathCallback = null;
                    return false;
                }
            }

            @Override
            public boolean onConsoleMessage(ConsoleMessage message) {
                android.util.Log.d("WhiteLionWeb", message.message() + " @ " +
                        message.sourceId() + ":" + message.lineNumber());
                return true;
            }
        });

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public android.webkit.WebResourceResponse shouldInterceptRequest(
                    WebView view, WebResourceRequest request) {
                return assetLoader.shouldInterceptRequest(request.getUrl());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return handleNavigation(request.getUrl());
            }

            @SuppressWarnings("deprecation")
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return handleNavigation(Uri.parse(url));
            }

            private boolean handleNavigation(Uri uri) {
                String scheme = uri.getScheme() == null ? "" : uri.getScheme();
                String host = uri.getHost() == null ? "" : uri.getHost();

                if ("https".equalsIgnoreCase(scheme) && ASSET_HOST.equalsIgnoreCase(host)) {
                    return false;
                }

                // Keep links back to the hosted White Lion app inside the bundled local app.
                if ("https".equalsIgnoreCase(scheme)
                        && "koromaalhajiabu.github.io".equalsIgnoreCase(host)
                        && uri.getPath() != null
                        && uri.getPath().startsWith("/white-lion-sme-business-os/")) {
                    String relative = uri.getPath().substring(
                            "/white-lion-sme-business-os/".length());
                    String localPath = APP_ASSET_URL.substring(0, APP_ASSET_URL.lastIndexOf('/') + 1)
                            + (relative.isEmpty() ? "index.html" : relative);
                    if (uri.getQuery() != null) localPath += "?" + uri.getQuery();
                    if (uri.getFragment() != null) localPath += "#" + uri.getFragment();
                    webView.loadUrl(localPath);
                    return true;
                }

                if ("mailto".equalsIgnoreCase(scheme) || "tel".equalsIgnoreCase(scheme)
                        || "https".equalsIgnoreCase(scheme)) {
                    try {
                        startActivity(new Intent(Intent.ACTION_VIEW, uri));
                    } catch (Exception e) {
                        android.util.Log.w("WhiteLionWeb", "No app for " + uri);
                    }
                }
                return true;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request,
                    WebResourceError error) {
                if (request.isForMainFrame()) showConnectionError();
            }

            @Override
            public void onReceivedHttpError(WebView view, WebResourceRequest request,
                    android.webkit.WebResourceResponse response) {
                if (request.isForMainFrame() && response.getStatusCode() >= 500) {
                    showConnectionError();
                }
            }
        });

        setContentView(webView);
        if (state != null && webView.restoreState(state) != null) return;
        // Load the packaged web application, not GitHub Pages. The app shell therefore
        // opens without internet; Supabase sync is available whenever connectivity returns.
        webView.loadUrl(APP_ASSET_URL);
    }

    private void showConnectionError() {
        if (isFinishing()) return;
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(36, 72, 36, 36);
        page.setBackgroundColor(Color.WHITE);

        TextView title = new TextView(this);
        title.setText("White Lion SME");
        title.setTextColor(Color.rgb(16, 26, 45));
        title.setTextSize(24);
        title.setTypeface(null, android.graphics.Typeface.BOLD);

        TextView message = new TextView(this);
        message.setText("The application files could not be opened. Retry, or reinstall the latest APK.");
        message.setTextColor(Color.rgb(55, 65, 81));
        message.setTextSize(16);
        message.setPadding(0, 18, 0, 22);

        Button retry = new Button(this);
        retry.setText("Retry");
        retry.setOnClickListener(v -> webView.loadUrl(APP_ASSET_URL));

        Button browser = new Button(this);
        browser.setText("Open web version");
        browser.setOnClickListener(v -> {
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(APP_URL)));
            } catch (Exception ignored) {}
        });

        page.addView(title);
        page.addView(message);
        page.addView(retry);
        page.addView(browser);
        setContentView(page);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == FILE_PICKER_REQUEST && filePathCallback != null) {
            Uri[] results = WebChromeClient.FileChooserParams.parseResult(resultCode, data);
            filePathCallback.onReceiveValue(results);
            filePathCallback = null;
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        if (webView != null) webView.saveState(outState);
        super.onSaveInstanceState(outState);
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (filePathCallback != null) {
            filePathCallback.onReceiveValue(null);
            filePathCallback = null;
        }
        if (webView != null) {
            webView.stopLoading();
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}