CREATE TABLE orders (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer   text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX orders_customer_idx ON orders (customer);

CREATE TABLE order_lines (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES orders (id),
    sku         text   NOT NULL,
    quantity    int    NOT NULL CHECK (quantity > 0),
    price_cents bigint NOT NULL
);
