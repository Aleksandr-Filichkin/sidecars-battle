package com.example.echo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;

@RestController
public class EchoController {
    private final String appName;

    public EchoController(@Value("${spring.application.name:echo}") String appName) {
        this.appName = appName;
    }

    @GetMapping("/internal/echo/{msg}/{delay}")
    public Mono<Map<String, Object>> echoPath(@PathVariable String msg, @PathVariable long delay) {
        Map<String, Object> payload = Map.of(
                "echo", msg,
                "ts", Instant.now().toString(),
                "app", appName
        );
        return Mono.just(payload)
                .delayElement(Duration.ofMillis(delay));
    }

    @GetMapping("/private/echo/{msg}/{delay}")
    public Mono<Map<String, Object>> internalEchoPath(@PathVariable String msg, @PathVariable long delay) {
        Map<String, Object> payload = Map.of(
                "echo", msg,
                "ts", Instant.now().toString(),
                "app", appName
        );
        return Mono.just(payload)
                .delayElement(Duration.ofMillis(delay));
    }

   

    @GetMapping("/info")
    public Mono<Map<String, Object>> info() {
        Map<String, Object> payload = Map.of(
                "message", "Spring WebFlux Echo Service",
                "app", appName,
                "ts", Instant.now().toString()
        );
        return Mono.just(payload);
    }
}