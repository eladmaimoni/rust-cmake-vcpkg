// use bridge::by2_add_safe;

fn main() {
    println!("Hello, world!");
    let x = 5;
    let y = 10;
    let result = bridge::by2_add_safe(x, y);
    println!("The result of adding {} and {} is {}", x, y, result);
}
