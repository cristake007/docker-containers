<?php

namespace App\Tests\Command;

use App\Entity\User;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Console\Application;
use Symfony\Bundle\FrameworkBundle\Test\KernelTestCase;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Tester\CommandTester;

/**
 * ADMIN_EMAIL / ADMIN_PASSWORD are read via #[Autowire(env: ...)], so
 * exercising different values means overriding the real environment before
 * each kernel boot -- there's no command-line input for them by design
 * (see App\Command\BootstrapAdminCommand): the admin account is entirely
 * environment-driven, never CLI-driven.
 */
final class BootstrapAdminCommandTest extends KernelTestCase
{
    /** @var array<string, string|false> */
    private array $originalEnv = [];

    protected function setUp(): void
    {
        foreach (['ADMIN_EMAIL', 'ADMIN_PASSWORD'] as $name) {
            $this->originalEnv[$name] = getenv($name);
        }
    }

    protected function tearDown(): void
    {
        foreach ($this->originalEnv as $name => $value) {
            $this->setEnv($name, false === $value ? null : $value);
        }
        parent::tearDown();
    }

    private function setEnv(string $name, ?string $value): void
    {
        if (null === $value) {
            putenv($name);
            unset($_ENV[$name], $_SERVER[$name]);

            return;
        }

        putenv("$name=$value");
        $_ENV[$name] = $value;
        $_SERVER[$name] = $value;
    }

    private function tester(): CommandTester
    {
        $kernel = self::bootKernel();
        $application = new Application($kernel);

        return new CommandTester($application->find('app:bootstrap-admin'));
    }

    private function purgeUsers(): void
    {
        static::getContainer()->get(EntityManagerInterface::class)
            ->createQuery('DELETE FROM App\Entity\User')->execute();
    }

    public function testCreatesTheAdminAccountAndIsIdempotent(): void
    {
        $this->setEnv('ADMIN_EMAIL', 'idempotent-admin@example.com');
        $this->setEnv('ADMIN_PASSWORD', 'a-perfectly-fine-password');

        $tester = $this->tester();
        $this->purgeUsers();
        self::assertSame(Command::SUCCESS, $tester->execute([]));

        // Running it again (as an operator rotating the password would)
        // must update the existing row, not create a second one.
        $tester = $this->tester();
        self::assertSame(Command::SUCCESS, $tester->execute([]));

        $em = static::getContainer()->get(EntityManagerInterface::class);
        $count = (int) $em->createQuery('SELECT COUNT(u) FROM App\Entity\User u')->getSingleScalarResult();
        self::assertSame(1, $count);

        $user = $em->getRepository(User::class)->findOneBy(['email' => 'idempotent-admin@example.com']);
        self::assertNotNull($user);
        self::assertContains('ROLE_ADMIN', $user->getRoles());
    }

    public function testCanonicalizesTheEmailToLowercase(): void
    {
        $this->setEnv('ADMIN_EMAIL', 'Mixed-Case@Example.com');
        $this->setEnv('ADMIN_PASSWORD', 'a-perfectly-fine-password');

        $tester = $this->tester();
        $this->purgeUsers();
        self::assertSame(Command::SUCCESS, $tester->execute([]));

        $em = static::getContainer()->get(EntityManagerInterface::class);
        $user = $em->getRepository(User::class)->findOneBy(['email' => 'mixed-case@example.com']);
        self::assertNotNull($user, 'email must be stored lowercased regardless of ADMIN_EMAIL casing');
    }

    public function testFailsWhenAdminEmailIsEmpty(): void
    {
        $this->setEnv('ADMIN_EMAIL', '');
        $this->setEnv('ADMIN_PASSWORD', 'a-perfectly-fine-password');

        $tester = $this->tester();
        self::assertSame(Command::FAILURE, $tester->execute([]));
    }

    public function testFailsWhenAdminPasswordIsEmpty(): void
    {
        $this->setEnv('ADMIN_EMAIL', 'admin@example.com');
        $this->setEnv('ADMIN_PASSWORD', '');

        $tester = $this->tester();
        self::assertSame(Command::FAILURE, $tester->execute([]));
    }

    public function testFailsValidationForAnInvalidEmailFormat(): void
    {
        $this->setEnv('ADMIN_EMAIL', 'not-an-email');
        $this->setEnv('ADMIN_PASSWORD', 'a-perfectly-fine-password');

        $tester = $this->tester();
        self::assertSame(Command::FAILURE, $tester->execute([]));
    }

    public function testFailsValidationForAPasswordShorterThanEightCharacters(): void
    {
        $this->setEnv('ADMIN_EMAIL', 'admin@example.com');
        $this->setEnv('ADMIN_PASSWORD', 'short');

        $tester = $this->tester();
        self::assertSame(Command::FAILURE, $tester->execute([]));
    }
}
