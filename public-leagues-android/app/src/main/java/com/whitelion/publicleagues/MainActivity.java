package com.whitelion.publicleagues;

import android.app.Activity;
import android.os.Bundle;
import android.view.View;
import android.webkit.*;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.graphics.Color;
import android.view.Gravity;

public class MainActivity extends Activity {
    private static final String HOME = "https://koromaalhajiabu.github.io/white-lion-sme-business-os/public-leagues.html";
    private WebView webView;
    private LinearLayout errorPanel;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.rgb(8, 55, 34));
        getWindow().setNavigationBarColor(Color.BLACK);
        buildScreen();
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setLoadsImagesAutomatically(true);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setAllowFileAccess(false);
        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    webView.setVisibility(View.GONE);
                    errorPanel.setVisibility(View.VISIBLE);
                }
            }
        });
        if (state == null) webView.loadUrl(HOME); else webView.restoreState(state);
    }

    private void buildScreen() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        webView = new WebView(this);
        root.addView(webView, new LinearLayout.LayoutParams(-1, 0, 1));
        errorPanel = new LinearLayout(this);
        errorPanel.setOrientation(LinearLayout.VERTICAL);
        errorPanel.setGravity(Gravity.CENTER);
        errorPanel.setPadding(32, 24, 32, 24);
        errorPanel.setBackgroundColor(Color.WHITE);
        TextView message = new TextView(this);
        message.setText("The directory could not be reached. Check your internet connection.");
        message.setTextColor(Color.DKGRAY);
        message.setGravity(Gravity.CENTER);
        errorPanel.addView(message);
        TextView retry = new TextView(this);
        retry.setText("TAP TO RETRY");
        retry.setTextColor(Color.rgb(8, 122, 67));
        retry.setGravity(Gravity.CENTER);
        retry.setPadding(20, 28, 20, 20);
        retry.setOnClickListener(v -> {
            errorPanel.setVisibility(View.GONE);
            webView.setVisibility(View.VISIBLE);
            webView.loadUrl(HOME);
        });
        errorPanel.addView(retry);
        root.addView(errorPanel, new LinearLayout.LayoutParams(-1, -2));
        errorPanel.setVisibility(View.GONE);
        setContentView(root);
    }

    @Override protected void onSaveInstanceState(Bundle out) {
        webView.saveState(out);
        super.onSaveInstanceState(out);
    }

    @Override public void onBackPressed() {
        if (webView.canGoBack()) webView.goBack(); else super.onBackPressed();
    }
}
