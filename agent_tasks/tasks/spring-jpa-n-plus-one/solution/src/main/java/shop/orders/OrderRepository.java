package shop.orders;

import java.util.List;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderRepository extends JpaRepository<Order, Long> {
    /** Orders with their lines in one query (a left join, so orders without lines are kept). */
    @EntityGraph(attributePaths = "lines")
    List<Order> findByCustomerOrderByIdAsc(String customer);
}
