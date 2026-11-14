package catalog.json;

import catalog.products.Money;
import tools.jackson.core.JsonGenerator;
import tools.jackson.databind.SerializationContext;
import tools.jackson.databind.ValueSerializer;

/** Money goes over the wire as "12.50 EUR", the format the storefront parses. */
class MoneySerializer extends ValueSerializer<Money> {
    @Override
    public void serialize(Money value, JsonGenerator gen, SerializationContext ctxt) {
        gen.writeString(value.display());
    }
}
