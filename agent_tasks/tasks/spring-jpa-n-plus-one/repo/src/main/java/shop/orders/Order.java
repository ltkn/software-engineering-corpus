package shop.orders;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "orders")
public class Order {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String customer;

    @OneToMany(mappedBy = "order")
    @OrderBy("id")
    private List<OrderLine> lines = new ArrayList<>();

    protected Order() {
    }

    public Long getId() {
        return id;
    }

    public String getCustomer() {
        return customer;
    }

    public List<OrderLine> getLines() {
        return lines;
    }
}
