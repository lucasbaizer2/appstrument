use super::ast::{ArrayExpression, Assignment, Literal, MemberExpression, MethodCall, Token};
use pest::{iterators::Pair, Parser};

#[derive(pest_derive::Parser)]
#[grammar = "slat/syntax.pest"]
pub struct SlatParser;

#[derive(thiserror::Error, Debug)]
pub enum ParserError {
    #[error("{0}")]
    InvalidSyntax(String),
}

fn parse_import(pair: Pair<Rule>) -> Token {
    let qualifiers = pair
        .into_inner()
        .map(|pair| pair.as_str().to_owned())
        .collect();
    Token::Import(qualifiers)
}

fn parse_string(pair: Pair<Rule>) -> Token {
    let str = pair.as_str().as_bytes();
    Token::Literal(Literal::String(
        String::from_utf8(str[1..str.len() - 1].to_vec()).expect("invalid string"),
    ))
}

fn parse_boolean(pair: Pair<Rule>) -> Token {
    Token::Literal(Literal::Boolean(pair.as_str() == "true"))
}

fn parse_integer(pair: Pair<Rule>) -> Token {
    let str = pair.as_str();
    Token::Literal(Literal::Integer(
        str.parse::<i64>().expect("invalid integer"),
    ))
}

fn parse_decimal(pair: Pair<Rule>) -> Token {
    let str = pair.as_str();
    Token::Literal(Literal::Decimal(
        str.parse::<f64>().expect("invalid decimal"),
    ))
}

fn parse_ident(pair: Pair<Rule>) -> Token {
    Token::Identifier(pair.as_str().to_string())
}

fn parse_method_call(pair: Pair<Rule>) -> Token {
    let mut tokens = pair.into_inner();
    let method_name = tokens.next().expect("unreachable").as_str();

    let mut args = Vec::new();
    for param in tokens {
        args.push(parse_expr(param));
    }

    Token::MethodCall(MethodCall {
        name: method_name.to_string(),
        args,
    })
}

fn parse_inner_member_expr(pair: Pair<Rule>) -> Token {
    match pair.as_rule() {
        Rule::method_call => parse_method_call(pair),
        Rule::ident => parse_ident(pair),
        // Rule::member_expr => parse_member_expr(pair),
        _ => unreachable!(),
    }
}

fn parse_array_expr(pair: Pair<Rule>) -> Token {
    let mut tokens = pair.into_inner();

    let array = tokens.next().expect("unreachable");
    let array = match array.as_rule() {
        Rule::member_expr => parse_member_expr(array),
        Rule::method_call => parse_method_call(array),
        Rule::ident => parse_ident(array),
        _ => unreachable!(),
    };
    Token::ArrayExpression(ArrayExpression {
        array: Box::new(array),
        index: Box::new(parse_expr(tokens.next().expect("unreachable"))),
    })
}

fn parse_member_expr(pair: Pair<Rule>) -> Token {
    let mut tokens = pair.into_inner();

    Token::MemberExpression(MemberExpression {
        owner: Box::new(parse_inner_member_expr(tokens.next().expect("unreachable"))),
        members: tokens.map(parse_inner_member_expr).collect(),
    })
}

fn parse_expr(pair: Pair<Rule>) -> Token {
    let inner_expr = pair.into_inner().next().expect("unreachable");
    match inner_expr.as_rule() {
        Rule::integer => parse_integer(inner_expr),
        Rule::boolean => parse_boolean(inner_expr),
        Rule::decimal => parse_decimal(inner_expr),
        Rule::string => parse_string(inner_expr),
        Rule::ident => parse_ident(inner_expr),
        Rule::array_expr => parse_array_expr(inner_expr),
        Rule::method_call => parse_method_call(inner_expr),
        Rule::member_expr => parse_member_expr(inner_expr),
        _ => unreachable!(),
    }
}

fn parse_assignment(pair: Pair<Rule>) -> Token {
    let mut tokens = pair.into_inner();

    Token::Assignment(Assignment {
        variable: tokens.next().expect("unreachable").as_str().to_owned(),
        expr: Box::new(parse_expr(tokens.next().expect("unreachable"))),
    })
}

pub fn parse(slat_code: &str) -> anyhow::Result<Vec<Token>> {
    let mut result = Vec::new();
    let inner_program = match SlatParser::parse(Rule::program, slat_code) {
        Ok(mut pairs) => pairs.next().expect("unreachable").into_inner(),
        Err(e) => return Err(ParserError::InvalidSyntax(format!("{}", e)).into()),
    };
    for pair in inner_program {
        match pair.as_rule() {
            Rule::import => result.push(parse_import(pair)),
            Rule::expr => result.push(parse_expr(pair)),
            Rule::assignment => result.push(parse_assignment(pair)),
            Rule::EOI => (),
            _ => unreachable!(),
        }
    }
    Ok(result)
}
