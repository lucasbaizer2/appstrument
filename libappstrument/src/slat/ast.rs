#[derive(Debug)]
pub enum Literal {
    Integer(i64),
    Decimal(f64),
    String(String),
    Boolean(bool),
}

#[derive(Debug)]
pub struct MethodCall {
    pub name: String,
    pub args: Vec<Token>,
}

#[derive(Debug)]
pub struct ArrayExpression {
    pub array: Box<Token>,
    pub index: Box<Token>,
}

#[derive(Debug)]
pub struct MemberExpression {
    pub owner: Box<Token>,
    pub members: Vec<Token>,
}

#[derive(Debug)]
pub struct Assignment {
    pub variable: String,
    pub expr: Box<Token>,
}

#[derive(Debug)]
pub enum Token {
    Identifier(String),
    Literal(Literal),
    Import(Vec<String>),
    ArrayExpression(ArrayExpression),
    MemberExpression(MemberExpression),
    MethodCall(MethodCall),
    Assignment(Assignment),
}
