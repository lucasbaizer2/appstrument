import 'package:appstrument/proto/data_model.pb.dart';
import 'package:flutter/material.dart';

Widget getJavaValueWidget(JavaValue baseValue, TextStyle? defaultStyle) {
  if (baseValue.valueType == JavaValue_JavaValueType.NULL_OBJECT) {
    return Text('null',
        style: const TextStyle(color: Colors.brown).merge(defaultStyle));
  }
  if (baseValue.hasDecimal()) {
    return Text(baseValue.decimal.toString(),
        style: const TextStyle(color: Colors.green).merge(defaultStyle));
  }
  if (baseValue.hasBoolean()) {
    return Text(baseValue.boolean.toString(),
        style: const TextStyle(color: Colors.blue).merge(defaultStyle));
  }
  if (baseValue.hasInteger()) {
    return Text(baseValue.integer.toString(),
        style: const TextStyle(color: Colors.green).merge(defaultStyle));
  }
  if (baseValue.hasString()) {
    return Text('"' + baseValue.string + '"',
        style: const TextStyle(color: Colors.brown).merge(defaultStyle));
  }
  if (baseValue.hasObjectType()) {
    return Text(
      '[object ' + baseValue.objectType + ']',
      style: const TextStyle(color: Colors.deepOrange).merge(defaultStyle),
    );
  }
  if (baseValue.hasList()) {
    var widgets = baseValue.list.items
        .map(
          (item) => WidgetSpan(
            child: getJavaValueWidget(item, defaultStyle),
          ),
        )
        .toList();
    var joined = [];
    for (var widget in widgets) {
      joined.add(widget);
      joined.add(const TextSpan(text: ', '));
    }
    if (joined.isNotEmpty) {
      joined.removeLast();
    }

    return RichText(
      text: TextSpan(
        children: [
          const TextSpan(text: '['),
          ...joined,
          const TextSpan(text: ']'),
        ],
        style: const TextStyle(color: Colors.black).merge(defaultStyle),
      ),
    );
  }
  return Text('NOT_YET_IMPLEMENTED', style: defaultStyle);
}
