#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Roda o bloco e devolve a NSException que ele lançar, ou nil.
/// O Swift não captura exceções do Objective-C: sem isto, uma falha do ScriptingBridge fecha o app.
NSException * _Nullable capturarExcecao(NS_NOESCAPE void (^bloco)(void));

NS_ASSUME_NONNULL_END
