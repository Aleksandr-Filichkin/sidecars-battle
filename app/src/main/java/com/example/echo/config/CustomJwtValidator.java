package com.example.echo.config;

import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;

import java.time.Instant;
import java.util.List;
import java.util.Arrays;

public class CustomJwtValidator implements OAuth2TokenValidator<Jwt> {

    @Override
    public OAuth2TokenValidatorResult validate(Jwt jwt) {
        Instant expiration = jwt.getExpiresAt();
        if (expiration != null && expiration.isBefore(Instant.now())) {
            OAuth2Error error = new OAuth2Error("expired_token", "Token has expired", null);
            return OAuth2TokenValidatorResult.failure(error);
        }

        if (!tokenHasUserScope(jwt)) {
            OAuth2Error error = new OAuth2Error("insufficient_scope", "Token must have 'user' scope", null);
            return OAuth2TokenValidatorResult.failure(error);
        }

        return OAuth2TokenValidatorResult.success();
    }

    private boolean tokenHasUserScope(Jwt jwt) {
        List<String> scopeList = jwt.getClaimAsStringList("scope");
        if (scopeList != null && scopeList.contains("user")) {
            return true;
        }

        String scopeString = jwt.getClaimAsString("scope");
        return scopeString != null
                && !scopeString.isBlank()
                && Arrays.asList(scopeString.split("\\s+")).contains("user");
    }
}