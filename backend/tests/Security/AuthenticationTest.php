<?php

namespace App\Tests\Security;

use App\Entity\User;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

final class AuthenticationTest extends WebTestCase
{
    private const ADMIN_EMAIL = 'admin@example.com';
    private const ADMIN_PASSWORD = 'test-admin-password';

    /**
     * json_encode() is typed to return string|false (encoding failure is
     * possible in general); every call site here encodes a literal array of
     * scalars, which can never fail, so this just narrows the type back to
     * what it always actually is instead of repeating the assertion.
     *
     * @param array<string, mixed> $data
     */
    private function jsonBody(array $data): string
    {
        return json_encode($data) ?: throw new \RuntimeException('json_encode failed');
    }

    /**
     * @return array<string, mixed>
     */
    private function jsonDecode(string|false $json): array
    {
        return json_decode($json ?: throw new \RuntimeException('empty response body'), true, flags: \JSON_THROW_ON_ERROR);
    }

    private function seedAdmin(): void
    {
        $container = static::getContainer();
        $em = $container->get(EntityManagerInterface::class);
        $hasher = $container->get(UserPasswordHasherInterface::class);

        $em->createQuery('DELETE FROM App\Entity\User')->execute();

        $user = new User();
        $user->setEmail(self::ADMIN_EMAIL);
        $user->setRoles(['ROLE_ADMIN']);
        $user->setPassword($hasher->hashPassword($user, self::ADMIN_PASSWORD));

        $em->persist($user);
        $em->flush();
    }

    public function testAnonymousMeReportsUnauthenticated(): void
    {
        $client = static::createClient();
        $client->request('GET', '/api/me');

        self::assertResponseIsSuccessful();
        self::assertJsonStringEqualsJsonString('{"authenticated":false}', $client->getResponse()->getContent() ?: '');
    }

    public function testLoginWithWrongPasswordIsRejected(): void
    {
        $client = static::createClient();
        $this->seedAdmin();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: $this->jsonBody(['email' => self::ADMIN_EMAIL, 'password' => 'wrong-password']),
        );

        self::assertResponseStatusCodeSame(401);
    }

    public function testUnknownEmailIsRejectedLikeAWrongPassword(): void
    {
        // A distinct error/response for "no such account" vs "wrong password"
        // would let an attacker enumerate valid emails -- both must look the
        // same from the outside.
        $client = static::createClient();
        $this->seedAdmin();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: $this->jsonBody(['email' => 'nobody@example.com', 'password' => self::ADMIN_PASSWORD]),
        );
        $unknownEmailStatus = $client->getResponse()->getStatusCode();
        $unknownEmailBody = $client->getResponse()->getContent();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: $this->jsonBody(['email' => self::ADMIN_EMAIL, 'password' => 'wrong-password']),
        );

        self::assertSame($unknownEmailStatus, $client->getResponse()->getStatusCode());
        self::assertSame($unknownEmailBody, $client->getResponse()->getContent());
    }

    public function testLoginIsCaseInsensitiveOnEmailAndEstablishesASession(): void
    {
        $client = static::createClient();
        $this->seedAdmin();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: $this->jsonBody(['email' => 'ADMIN@EXAMPLE.COM', 'password' => self::ADMIN_PASSWORD]),
        );
        self::assertResponseIsSuccessful();

        $client->request('GET', '/api/me');
        $body = $this->jsonDecode($client->getResponse()->getContent());

        self::assertTrue($body['authenticated']);
        self::assertSame(self::ADMIN_EMAIL, $body['email']);
    }

    public function testLogoutClearsTheSessionCookie(): void
    {
        $client = static::createClient();
        $this->seedAdmin();

        $client->request(
            'POST',
            '/api/login',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: $this->jsonBody(['email' => self::ADMIN_EMAIL, 'password' => self::ADMIN_PASSWORD]),
        );
        self::assertResponseIsSuccessful();

        $client->request('POST', '/api/logout');
        self::assertResponseIsSuccessful();

        $cookie = $client->getResponse()->headers->getCookies()[0] ?? null;
        self::assertNotNull($cookie, 'logout must set a cookie header to clear BEARER');
        self::assertSame('BEARER', $cookie->getName());
        self::assertLessThan(time(), $cookie->getExpiresTime());

        // The cleared cookie must actually take effect for the next request
        // on the same client -- not just be present in this one response.
        $client->request('GET', '/api/me');
        $body = $this->jsonDecode($client->getResponse()->getContent());
        self::assertFalse($body['authenticated']);
    }
}
