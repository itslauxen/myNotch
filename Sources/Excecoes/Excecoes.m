#import "Excecoes.h"

NSException *capturarExcecao(NS_NOESCAPE void (^bloco)(void)) {
    @try {
        bloco();
        return nil;
    } @catch (NSException *excecao) {
        return excecao;
    }
}
