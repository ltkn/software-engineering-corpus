CREATE TABLE items (
    id       bigserial PRIMARY KEY,
    sku      text    NOT NULL UNIQUE,
    quantity integer NOT NULL CHECK (quantity >= 0),
    version  bigint  NOT NULL DEFAULT 0
);

CREATE TABLE orders (
    id       bigserial PRIMARY KEY,
    customer text    NOT NULL,
    sku      text    NOT NULL,
    quantity integer NOT NULL
);
