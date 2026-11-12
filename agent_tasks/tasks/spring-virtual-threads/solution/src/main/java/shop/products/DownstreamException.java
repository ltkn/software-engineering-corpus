package shop.products;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(HttpStatus.BAD_GATEWAY)
public class DownstreamException extends RuntimeException {
    public DownstreamException(String message, Throwable cause) {
        super(message, cause);
    }
}
