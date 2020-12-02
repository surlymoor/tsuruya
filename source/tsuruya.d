///
module tsuruya;

import std.range : ElementEncodingType, ElementType, isInputRange;
import std.traits : arity, isAggregateType, isCallable, isType, Parameters, ReturnType, Unqual;

@safe:

/**
	Command-line parameter

	Params:
		identifier = The parameter's identifier used in the command-line interface and programming interface.
		T = The type of the value the parameter will take.
*/
struct Parameter(string identifier, T = string)
{
	mixin ParameterImpl!(identifier, T);
}

/**
	Command-line parameter

	Params:
		identifier = The parameter's identifier used in the command-line interface and programming interface.
		processor = A callable object that processes the value given to the parameter. The type of the parameter's
			value is determined by the processor's return type.
*/
struct Parameter(string identifier, alias processor)
if (isValidParameterProcessor!processor)
{
	mixin ParameterImpl!(identifier, ReturnType!processor);
	/// Processes the value of the corresponding argument
	alias proc = processor;
}

/**
	Determines if a callable object may be used as a processor of command-line parameters and options.

	As mentioned, the object must be callable; it must take only one argument of type string; and it must return a
	value.

	Params:
		processor = The candidate.
*/
enum isValidParameterProcessor(alias processor) = isCallable!processor && arity!processor == 1
	&& is(Parameters!processor[0] == string) && !is(ReturnType!processor == void);

/// Command-line parameter's implementation
private mixin template ParameterImpl(string identifier, T)
{
	/// The parameter's name as used in the command-line interface and in the programming interface.
	static immutable id = identifier;
	/// The parameter's value, i.e. the value on which the parameter takes.
	T value;
}

///
unittest
{
	// OK: It's a lambda, takes only one string, and returns a value.
	static assert(isValidParameterProcessor!((string value) => 42));
	// Invalid: It's a lambda, and it resolves to a value, but it takes multiple arguments.
	static assert(!isValidParameterProcessor!((string value, string otherValue) => 42));
	// Invalid: It's a template.
	static assert(!isValidParameterProcessor!((value) => 42));
	// Invalid: It's a lambda, and it returns a value, but it takes a non-string argument.
	static assert(!isValidParameterProcessor!((int value) => 42));
	// Invalid: It's a lambda, takes only one string, but it doesn't resolve to anything.
	static assert(!isValidParameterProcessor!((string value) { return; }));
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		T = The type of the value the option will take.
		defaultValue = The value the option will take if it's not specified in the command-line arguments.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, T, T defaultValue, optionSettings...)
{
	mixin OptionImpl!(nameSpecification, T, defaultValue, optionSettings);
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		T = The type of the value the option will take.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, T, optionSettings...)
{
	mixin OptionImpl!(nameSpecification, T, T.init, optionSettings);
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		defaultValue = The value the option will take if it's not specified in the command-line arguments. The type of
			the option's value will be deduced from this default value.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, alias defaultValue, optionSettings...)
if (!isType!defaultValue && !isValidParameterProcessor!defaultValue)
{
	mixin OptionImpl!(nameSpecification, typeof(defaultValue), defaultValue, optionSettings);
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		processor = A callable object that processes value given to the option. The type of the option's value is
			determined by the processor's return type.
		defaultValue = The value the option will take if it's not specified in the command-line arguments.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, alias processor, alias defaultValue, optionSettings...)
if (isValidParameterProcessor!processor & !isType!defaultValue)
{
	mixin OptionImpl!(nameSpecification, ReturnType!processor, defaultValue, optionSettings);
	/// Processes the option's given value.
	alias proc = processor;
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		processor = A callable object that processes value given to the option. The type of the option's value is
			determined by the processor's return type.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, alias processor, optionSettings...)
if (isValidParameterProcessor!processor)
{
	mixin OptionImpl!(nameSpecification, ReturnType!processor, ReturnType!processor.init, optionSettings);
	/// Processes the option's given value.
	alias proc = processor;
}

/// Command-line option's implementation
private mixin template OptionImpl(string nameSpecification, T, alias defaultValue, settings...)
{
	mixin OptionNames!nameSpecification;
	mixin OptionSettings!settings;
	///
	static immutable nameSpec = nameSpecification;
	///
	T value = defaultValue;
}

/// Definitions of an option's various names derived from `nameSpecification`.
private mixin template OptionNames(string nameSpecification)
{
	import std.algorithm : splitter, until;
	import std.conv : to;
	static immutable longName = nameSpecification.until("|").until("+").to!string;
	static immutable shortName = nameSpecification.splitter('|').shortName;
}

unittest
{
	{
		mixin OptionNames!"option";
		static assert(longName == "option");
		static assert(shortName.length == 0);
	}
	{
		mixin OptionNames!"option|o";
		static assert(longName == "option");
		static assert(shortName == "o");
	}
	{
		mixin OptionNames!"option+";
		static assert(longName == "option");
		static assert(shortName.length == 0);
	}
	{
		mixin OptionNames!"option|o+";
		static assert(longName == "option");
		static assert(shortName == "o");
	}
	{
		mixin OptionNames!"option|o|setting+";
		static assert(longName == "option");
		static assert(shortName == "o");
	}
}

/**
	Returns the first element of a range that consists of one character and thus is considered a "short name".

	Params:
		range = An input range whose elements are convertible to `char` arrays. It is assumed that every element does
			not contain a bar '|'.
*/
pure
private auto shortName(R)(R range)
if (isInputRange!R && is(Unqual!(ElementEncodingType!(ElementType!R)) : char))
{
	import std.algorithm : filter, map, until;
	import std.conv : to;
	import std.range : front, walkLength;
	auto result = range.map!(r => r.until("+")).filter!(r => r.walkLength == 1);
	if (result.empty) return "";
	else return result.front.to!string;
}

/// Field definitions of option settings
private mixin template OptionSettings(settings...)
{
	import std.traits : getSymbolsByUDA;
	static foreach (Setting; getSymbolsByUDA!(tsuruya, OptionSetting))
	{
		mixin(q{static immutable }, Setting.id, q{ = getSettingValue!(Setting, settings);});
	}
}

///
private template getSettingValue(Setting, settings...)
{
	import std.format : format;
	import std.meta : staticIndexOf, staticMap;
	enum idx = staticIndexOf!(Setting, staticMap!(TypeOf, settings));
	static if (idx == -1) enum getSettingValue = Setting.defVal;
	else enum getSettingValue = settings[idx].value;
}

/// Resolves to the type of `instance`.
private alias TypeOf(alias instance) = typeof(instance);

/// A category under which the option is placed in the help text.
@OptionSetting
struct OptionCategory
{
	mixin OptionSettingImpl!("category", string, "");
}
/// A description of the option as seen in the help text
@OptionSetting
struct OptionDesc
{
	mixin OptionSettingImpl!("desc", string, "");
}
/// A more elaborated description of the option
@OptionSetting
struct OptionHelp
{
	mixin OptionSettingImpl!("help", string, "");
}
/// A signal as to whether the option is required to be present in the command-line arguments.
@OptionSetting
struct OptionRequired
{
	mixin OptionSettingImpl!("required", bool);
}

/// Attribute to identify aggregates as option settings
private enum OptionSetting;

/// Option setting implementation
private mixin template OptionSettingImpl(string identifier, T, T defaultValue = T.init)
{
	private static immutable id = identifier;
	private static immutable defVal = defaultValue;
	/// The option setting's value
	auto value = defaultValue;
}

///
auto parseArgs(CLIObjects...)(string[] args)
{
	import std.getopt : config, getopt;
	import std.meta : Filter;

	alias Parameters = Filter!(isParameter, CLIObjects);
	alias Options = Filter!(isOption, CLIObjects);
	Parameters params;
	Options opts;
}

/// Determines whether `T` may be considered a command-line parameter.
template isParameter(T)
if (isAggregateType!T)
{
	import std.traits : hasMember, hasStaticMember;
	static if (!hasStaticMember!(T, "id") || !is(typeof(T.id) == immutable(string)))
		enum isParameter = false;
	else static if (!hasMember!(T, "value"))
		enum isParameter = false;
	else enum isParameter = true;
}

/// Determines whether `T` may be considered a command-line option.
template isOption(T)
if (isAggregateType!T)
{
	import std.traits : hasMember, hasStaticMember;
	static if (!hasStaticMember!(T, "category") || !is(typeof(T.category) == immutable(string)))
		enum isOption = false;
	else static if (!hasStaticMember!(T, "desc") || !is(typeof(T.desc) == immutable(string)))
		enum isOption = false;
	else static if (!hasStaticMember!(T, "help") || !is(typeof(T.help) == immutable(string)))
		enum isOption = false;
	else static if (!hasStaticMember!(T, "required") || !is(typeof(T.required) == immutable(bool)))
		enum isOption = false;
	else static if (!hasStaticMember!(T, "longName") || !is(typeof(T.longName) == immutable(string)))
		enum isOption = false;
	else static if (!hasStaticMember!(T, "shortName") || !is(typeof(T.shortName) == immutable(string)))
		enum isOption = false;
	else static if (!hasStaticMember!(T, "nameSpec") || !is(typeof(T.nameSpec) == immutable(string)))
		enum isOption = false;
	else static if (!hasMember!(T, "value"))
		enum isOption = false;
	else enum isOption = true;
}