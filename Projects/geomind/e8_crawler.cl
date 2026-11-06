// Projects/geomind/e8_crawler.cl
// Autonomous Domain-Bounded Recursive Web Crawler (--crawl)

include "src/std/geom.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/fs.cl";

extern fn Sleep(ms: float);

// ============================================================================
// PHASE 4.1: AUTONOMOUS DOMAIN-BOUNDED RECURSIVE WEB CRAWLER (--crawl)
// ============================================================================
// Extracts the domain host from an http:// or https:// URL
fn geomind_crawl_extract_domain(url: string) -> string {
    var rest = url;
    let ulen = cartan_string_length(url);
    if (cartan_string_starts_with(url, "https://") == 1.0) {
        rest = cartan_string_substring(url, 8.0, ulen);
    } else if (cartan_string_starts_with(url, "http://") == 1.0) {
        rest = cartan_string_substring(url, 7.0, ulen);
    }
    let slash_idx = cartan_string_index_of(rest, "/");
    if (slash_idx > 0.0) {
        return cartan_string_substring(rest, 0.0, slash_idx);
    }
    return rest;
}

// Extracts same-domain href links from raw HTML into a vector of strings
fn geomind_crawl_extract_same_domain_links(html: string, base_domain: string) -> ptr {
    let links = cartan_tree_create();
    let hlen = cartan_string_length(html);
    if (hlen < 10.0) { return links; }
    var pos = 0.0;
    var idx = 0.0;
    var start_q = 0.0;
    var end_q = 0.0;
    var cand = "";
    var cand_dom = "";
    var found_cnt = 0.0;
    while (pos < hlen && found_cnt < 8.0) {
        idx = cartan_string_index_of_offset_ignore_case(html, "href=\"http", pos);
        if (idx < 0.0) {
            break;
        }
        start_q = idx + 6.0;
        end_q = cartan_string_index_of_offset(html, "\"", start_q);
        if (end_q > start_q) {
            cand = cartan_string_substring(html, start_q, end_q);
            cand_dom = geomind_crawl_extract_domain(cand);
            if (cartan_string_eq(cand_dom, base_domain) == 1.0) {
                cartan_tree_push(links, cand);
                found_cnt = found_cnt + 1.0;
            }
            pos = end_q + 1.0;
        } else {
            break;
        }
    }
    return links;
}

// Strips <script>, <style>, and HTML tags from raw HTML into clean normalized UTF-8 text
fn geomind_crawl_strip_html_to_text(html: string) -> string {
    let n = cartan_string_length(html);
    if (n <= 0.0) { return ""; }
    var out = "";
    var in_tag = 0.0;
    var last_space = 1.0;
    var i = 0.0;
    var ch = 0.0;
    while (i < n) {
        ch = cartan_byte_at(html, i);
        if (ch == 60.0) { // '<'
            in_tag = 1.0;
        } else if (ch == 62.0) { // '>'
            in_tag = 0.0;
            if (last_space == 0.0) {
                out = cartan_string_concat(out, " ");
                last_space = 1.0;
            }
        } else if (in_tag == 0.0) {
            if (ch == 10.0 || ch == 13.0 || ch == 9.0 || ch == 32.0) {
                if (last_space == 0.0) {
                    out = cartan_string_concat(out, " ");
                    last_space = 1.0;
                }
            } else if (ch >= 32.0 && ch <= 126.0) {
                out = cartan_string_concat(out, cartan_char_from_code(ch));
                last_space = 0.0;
            }
        }
        i = i + 1.0;
    }
    return out;
}

// Fetches raw HTML from a URL (or local file path for offline testing)
fn geomind_crawl_fetch_url(url: string) -> string {
    if (cartan_file_exists(url) == 1.0) {
        return cartan_read_file(url);
    }
    let tmp_file = "scratch/geomind_crawl_page.tmp";
    var cmd = "powershell -NoProfile -Command \"try { (Invoke-WebRequest -Uri '";
    cmd = cartan_string_concat(cmd, url);
    cmd = cartan_string_concat(cmd, "' -UseBasicParsing -TimeoutSec 10).Content | Out-File -FilePath '");
    cmd = cartan_string_concat(cmd, tmp_file);
    cmd = cartan_string_concat(cmd, "' -Encoding utf8 } catch { '' | Out-File -FilePath '");
    cmd = cartan_string_concat(cmd, tmp_file);
    cmd = cartan_string_concat(cmd, "' -Encoding utf8 }\"");
    cartan_system(cmd);
    if (cartan_file_exists(tmp_file) == 1.0) {
        return cartan_read_file(tmp_file);
    }
    return "";
}

// Autonomous Domain-Bounded Recursive Web Crawler & Markov-Lagrangian Trainer
fn geomind_crawl_and_train(
    url: string,
    start_domain: string,
    recurse: float,
    depth: float,
    max_depth: float,
    epochs: float,
    visualize: float
) -> float {
    if (depth > max_depth) { return 0.0; }
    var dom = start_domain;
    if (cartan_string_length(dom) == 0.0) {
        dom = geomind_crawl_extract_domain(url);
    }
    printf("[CARTAN-E8 Crawler] Fetching (depth %.0f/%.0f, domain='%s'): %s\n", depth, max_depth, dom, url);
    cartan_flush(0.0);

    let html = geomind_crawl_fetch_url(url);
    let clean_text = geomind_crawl_strip_html_to_text(html);
    let text_len = cartan_string_length(clean_text);
    if (text_len < 8.0) {
        printf("[CARTAN-E8 Crawler] Skipping empty/short response (%.0f bytes).\n", text_len);
        return 0.0;
    }

    printf("[CARTAN-E8 Crawler] Extracted %.0f bytes of clean UTF-8 text. Running %.0f Markov-Lagrangian epochs...\n", text_len, epochs);
    cartan_flush(0.0);
    let final_action = geomind_byte_latent_train_corpus(clean_text, epochs, 0.03, visualize);
    printf("[CARTAN-E8 Crawler] Completed %.0f epochs on %s -> Final Lagrangian Action S = %.6f\n", epochs, url, final_action);
    cartan_flush(0.0);

    if (visualize == 1.0) {
        geomind_visualizer_export_html("manifold_relaxation.html", url);
        printf("[CARTAN-E8 Visualizer] Exported live manifold relaxation plot to manifold_relaxation.html\n");
        cartan_flush(0.0);
    }

    if (recurse == 1.0 && depth < max_depth) {
        let sub_links = geomind_crawl_extract_same_domain_links(html, dom);
        let n_links = cartan_tree_len_f(sub_links);
        var li = 0.0;
        var child_url = "";
        while (li < n_links) {
            child_url = cartan_tree_get(sub_links, li);
            if (cartan_string_eq(child_url, url) == 0.0) {
                Sleep(150.0);
                geomind_crawl_and_train(child_url, dom, recurse, depth + 1.0, max_depth, epochs, visualize);
            }
            li = li + 1.0;
        }
    }
    return final_action;
}
