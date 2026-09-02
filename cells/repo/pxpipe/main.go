// Loopback Anthropic proxy for Hermes: strips the /anthropic prefix Hermes
// requires on a non-Anthropic base_url (runtime_provider.py:151), which
// upstream pxpipe forwards verbatim and api.anthropic.com 404s.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"

	pxpipe "github.com/evan-choi/pxpipe-go"
)

type ctxKey struct{}

type observation struct {
	model   string
	applied bool
	reason  pxpipe.Reason
	detail  string
	saved   int
}

func main() {
	port := flag.Int("port", 47821, "loopback port")
	flag.Parse()

	var upstream *url.URL
	if raw := os.Getenv("ANTHROPIC_BASE_URL"); raw != "" {
		u, err := url.Parse(raw)
		if err != nil {
			log.Fatalf("ANTHROPIC_BASE_URL: %v", err)
		}
		upstream = u
	}
	if os.Getenv("PXPIPE_MODELS") == "" {
		pxpipe.SetAllowedModelBases([]string{"*"})
	}

	handler := pxpipe.NewHandler(pxpipe.HandlerOptions{
		AnthropicUpstream: upstream,
		ProtocolOf: func(path string) pxpipe.Protocol {
			return pxpipe.DefaultProtocolOf(strings.TrimPrefix(path, "/anthropic"))
		},
		RewritePath: func(path string, _ pxpipe.Protocol) string {
			return strings.TrimPrefix(path, "/anthropic")
		},
		OnResult: func(r *http.Request, res *pxpipe.TransformResult) {
			o, _ := r.Context().Value(ctxKey{}).(*observation)
			if o == nil || res == nil {
				return
			}
			o.model, o.applied, o.reason, o.detail = res.Model, res.Applied, res.Reason, res.Detail
			if i := res.Info; i != nil {
				// Same estimate as upstream internal/app/server.go estimatedSaving.
				if i.BaselineImagedTokens > 0 || i.ImageTokens > 0 {
					o.saved = i.BaselineImagedTokens - i.ImageTokens - i.NativeInjectedTokens
				} else if i.CompressedChars > 0 && i.ImagePixels > 0 {
					o.saved = i.CompressedChars/4 - i.ImagePixels/(28*28)
				}
			}
		},
		OnResponseComplete: func(r *http.Request, res pxpipe.ResponseResult) {
			o, _ := r.Context().Value(ctxKey{}).(*observation)
			if o == nil {
				return
			}
			line := fmt.Sprintf("%d %s model=%s applied=%t", res.StatusCode, r.URL.Path, o.model, o.applied)
			if !o.applied {
				line += fmt.Sprintf(" reason=%s", o.reason)
				if o.detail != "" {
					line += " " + o.detail
				}
			} else {
				line += fmt.Sprintf(" saved=%d", o.saved)
			}
			if u := res.Usage; u != nil {
				line += fmt.Sprintf(" in=%d cache_read=%d cache_write=%d out=%d",
					u.InputTokens, u.CacheReadInputTokens, u.CacheCreationInputTokens, u.OutputTokens)
			}
			log.Println(line)
		},
	})

	addr := fmt.Sprintf("127.0.0.1:%d", *port)
	log.Printf("listening on %s; model.base_url: http://%s/anthropic", addr, addr)
	log.Fatal(http.ListenAndServe(addr, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Usage is read from the response body; a compressed stream would hide it.
		if strings.HasSuffix(r.URL.Path, "/messages") {
			r.Header.Set("Accept-Encoding", "identity")
		}
		handler.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, &observation{})))
	})))
}
